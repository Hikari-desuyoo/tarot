require 'uri'
require 'net/http'
require 'json'
require 'io/console'
require 'date'
require 'yaml'

# Módulo para interagir com a API do Metabase.
module Tarot
  # Exceção base do Tarot para suprimir backtracing.
  class TarotError < StandardError
    def backtrace
    end
  end

  # Módulo para interagir com a configuração do tarot local do usuário.
  module Config
    # Exceção levantada quando a configuração do usuário (localizado na tarot_spec.rb) falha.
    class ConfigError < TarotError
    end

    module_function
    # Estrutura para representar uma configuração de usuário.
    Data = Struct.new(:session_expire_days, :url, :database_aliases)

    # Usa um bloco, normalmente definido na tarot_spec.rb, para popular as configurações de usuário.
    #
    # @example Exemplo
    #   Config.build do |config|
    #     config.session_expire_days = 13
    #     config.url = 'https://metabase.mycompany.com'
    #     config.database_aliases = {}
    #   end
    #
    # @yieldreturn [Hash] Bloco que recebe um Tarot::Config::Data e modifica seus valores.
    # @return [void]
    # @raise [ConfigError] Se alguma configuração estiver faltando após a execução do bloco.
    def build(&block)
      @data = Data.new()
      block.call(@data)

      if @data.session_expire_days.nil?
        raise ConfigError, "Tarot config is missing 'session_expire_days'"
      end

      if @data.url.nil?
        raise ConfigError, "Tarot config is missing 'url'"
      end

      if @data.database_aliases.nil?
        raise ConfigError, "Tarot config is missing 'database_aliases'"
      end

      @data.session_expire_days.freeze
      @data.url = URI(@data.url).freeze
      @data.database_aliases.freeze

      @built = true
    end

    # Retorna as configurações de usuário
    # @return [Config::Data] Resultado da consulta.
    # @raise [ConfigError] Se as configurações ainda não foram definidas via Config.build.
    def data
      return @data unless @built.nil?

      raise ConfigError, 'Tarot is not properly configured, check tarot_spec.rb'
    end
  end

  # Caminho para o arquivo que carrega o token de autenticação do usuário + a data de expiração do token
  SECRET_TOKEN_PATH = "#{Dir.pwd}/.secret_token".freeze

  # Exceção levantada quando a autenticação falha.
  class LoginError < TarotError
  end

  # Exceção levantada quando uma database não é encontrada na API. Imprime na tela quais são as database disponíveis.
  class DatabaseNotFound < TarotError
  end

  # Exceção levantada quando o endpoint de query retornou erros. Vem com informações sobre o erro que ocorreu, caso a API disponibilize.
  class QueryError < TarotError
  end

  # Estrutura para representar uma database na API.
  Database = Struct.new(:id, :name) do
    def inspect
      "<Metabase::Database id=#{id.inspect}, name=#{name.inspect}>"
    end

    def to_s
      "'#{name}'(id #{id})"
    end

    # Mesmo que Tarot.query!(esse_banco, sql)
    # Executa uma consulta SQL e retorna o resultado. Levanta erro conforme resposta da API.
    # @param sql [String] Consulta SQL a ser executada.
    # @return [Object] Resultado da consulta.
    # @raise [QueryError] Se ocorrer um erro na consulta.
    def query!(sql)
      Tarot.query!(self, sql)
    end

    # Mesmo que Tarot.query(esse_banco, sql)
    # Executa uma consulta SQL e retorna o resultado.
    # @param sql [String] Consulta SQL a ser executada.
    # @return [Object] Resultado da API contendo a resposta da consulta ou um JSON com os erros que ocorreram.
    def query(sql)
      Tarot.query(self, sql)
    end
  end

  module_function

  # Grava os resultados de um bloco em um arquivo YAML com o mesmo nome passado pelo argumento filepath (porém terminando em .yaml), incluindo metadados de quando foi gerado, e do script que gerou o arquivo.
  #
  # @example Exemplo
  #   # exemplos/test.rb
  #   consultation(__FILE__) do
  #     db('minha db').query!('SELECT * FROM plans WHERE id = 3;')
  #   end
  #   # Isto irá criar um arquivo 'exemplos/test.yaml' com os resultados do bloco e metadados.
  #
  # @param filepath [String] Caminho do arquivo de origem, cujo conteúdo será usado nos metadados. É esperado que se preencha com __FILE__.
  # @yieldreturn [Hash] Bloco que retorna um hash com os dados a serem gravados.
  # @return [void]
  def consultation(filepath, &block)
    target_file = filepath.gsub(/\.rb\z/, '.yaml')

    File.write(target_file, YAML.dump({
      metadata: {
        generated_at: DateTime.now.iso8601,
        generated_by: File.read(filepath)
      },
      results: block.call()
    }))
    puts "Recorded #{target_file}"
  end

  # Encontra uma database pelo nome/alias.
  # @param name [String] Nome ou alias da database.
  # @return [Database] A database encontrada.
  # @raise [DatabaseNotFound] Se a database não for encontrada.
  def database(name)
    if Config.data.database_aliases.keys.include?(name.to_sym)
      name = Config.data.database_aliases[name.to_sym]
    end

    result = databases.find { |d| d.name == name }

    unless result
      message = <<~TEXT

        Database not found: #{name}
        To see available databases, run: tarot dbs
      TEXT

      raise DatabaseNotFound, message
    end

    result
  end

  alias db database

  # Retorna uma lista do nome de todos os nomes de databases disponíveis. Caso exista um alias para um nome, ele substituirá o nome.
  # @return [String] String com o nomes das databases.
  def database_names
    names = Tarot.databases.map(&:name)
    aliases = Tarot::Config.data.database_aliases.keys.map(&:to_s)

    names.filter! do |name|
      !Tarot::Config.data.database_aliases.values.include?(name)
    end

    (names + aliases)
  end

  # Retorna uma lista de todas as databases disponíveis.
  # @return [Array<Database>] Array de objetos Database.
  def databases
    unless @databases
      uri = Config.data.url + '/api/database'
      http = Net::HTTP.new(uri.hostname, uri.port)
      http.use_ssl = uri.scheme == 'https'

      request = Net::HTTP::Get.new(uri)
      request['Accept'] = 'application/json'
      request['X-Metabase-Session'] = fetch_token

      response = http.request(request)
      @databases = JSON.parse(response.body).map do |payload|
        Database.new(payload['id'], payload['name'])
      end
    end
    @databases
  end

  # Executa uma consulta SQL e retorna o resultado. Levanta erro conforme resposta da API.
  # @param database [Database] Base de dados onde executar a consulta.
  # @param sql [String] Consulta SQL a ser executada.
  # @return [Object] Resultado da consulta.
  # @raise [QueryError] Se ocorrer um erro na consulta.
  def query!(database, sql)
    result = query(database, sql)
    raise QueryError, result['error'] if result.is_a?(Hash) && result['error']

    result
  end

  # Executa uma consulta SQL e retorna o resultado.
  # @param database [Database] Base de dados onde executar a consulta. Use Tarot.database('minah db') para conseguir esse objeto.
  # @param sql [String] Consulta SQL a ser executada.
  # @return [Object] Resultado da API contendo a resposta da consulta ou um JSON com os erros que ocorreram.
  def query(database, sql)
    uri = Config.data.url + '/api/dataset/json'
    http = Net::HTTP.new(uri.hostname, uri.port)
    http.use_ssl = uri.scheme == 'https'

    request = Net::HTTP::Post.new(uri,
     'Accept' => 'application/json',
     'X-Metabase-Session' => fetch_token
    )
    request.content_type = 'application/x-www-form-urlencoded'

    params = {
      'query': JSON.dump({
        'type' => 'native',
        'database' => database.id,
        'parameters' => [],
        'native' => {
          'query' => sql,
          'template-tags' => {}
        },
      })
    }
    request.body = URI.encode_www_form(params)
    response = http.request(request)
    JSON.parse(response.body) rescue response.body
  end

  # Limpa o token de sessão, armazenado localmente.
  def clear_token
    File.write(SECRET_TOKEN_PATH, '{}')
  end

  # Imprime a cheatsheet na tela
  def print_cheatsheet
    puts <<~TEXT
                                      Tarot Cheatsheet

        ┌─────────────────────────┬────────────────────────────────────────────────────┐
        │ Ver databases           │ puts database_names                                │
        │ Puxar database por nome | db('nome')                                         │
        │ Fazer query             │ minha_db.query!('SELECT * FROM mytable')           │
        │ Limpar dados de sessão  │ clear_token                                        │
        │ Ver essa mensagem       │ print_cheatsheet                                   │
        └─────────────────────────┴────────────────────────────────────────────────────┘
    TEXT
  end

  # Obtém o token de sessão do Metabase, solicitando ao usuário se necessário.
  # @return [String] Token de sessão.
  def fetch_token
    token_json = File.exist?(SECRET_TOKEN_PATH) ? JSON.load(File.read(SECRET_TOKEN_PATH)) : {}
    token = token_json['token']

    if token.nil?
      uri = Config.data.url + '/api/session'
      http = Net::HTTP.new(uri.hostname, uri.port)
      http.use_ssl = uri.scheme == 'https'

      request = Net::HTTP::Post.new(uri, 'Content-Type' => 'application/json')
      login = {}
      puts 'Login to Metabase'
      print 'Username: '
      login['username'] = STDIN.gets.chomp
      print 'Password: '
      login['password'] = STDIN.noecho(&:gets).chomp
      puts "\n\n"

      request.body = JSON.dump(login)
      begin
        response = http.request(request)
      rescue OpenSSL::SSL::SSLError
        puts "#{Config.data.url.to_s} seems to be unreachable at the moment"
      end

      token = JSON.parse(response.body)['id']

      raise(LoginError, 'Wrong credentials') if token.nil?

      File.write(SECRET_TOKEN_PATH, JSON.dump(token: token, expire_at: DateTime.now + Config.data.session_expire_days))
      puts 'Authorized! :>'
    else
      expire_at = DateTime.parse(token_json['expire_at'])
      if DateTime.now >= expire_at
        puts 'Your token expired'
        clear_token
        fetch_token
      end
    end

    token
  end
end
