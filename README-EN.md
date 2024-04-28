<h1 align="center">🔮 Tarot 🔮</h1>

<p align="center">To find out what's happening in your database, consulting the <b>Tarot</b> can be a good idea!</p>

---

[![Gem Version](https://badge.fury.io/rb/metabase_tarot.svg)](https://badge.fury.io/rb/metabase_tarot)

> [!WARNING]
> The name of the gem in RubyGems is "**metabase_tarot**", not "tarot". Be careful!

### ⚝ Elevator pitch

Tarot is a gem for Ruby 3.0 designed to connect directly to a Metabase application using their API. In this section, I explain some reasons to use Tarot.

Sometimes, using the Metabase front-end might not be the best option. With Tarot, the user does not need to navigate slowly to the page they are looking for; they can just run the query quickly and get their result. An extra point for Tarot in this case is that usually a single Metabase page makes several API requests, whereas with Tarot the user has control over this and can avoid unnecessary requests that can take time especially in critical situations of application slowness.

With tarot, since the request is made by a script that the user writes, it is possible to mix the results of several queries on various databases and use Ruby code between the requests.

### ⚝ Quickstart

<div align="center">
  <img src="example.gif" alt="Example" width="90%">
</div>

With Ruby 3.0 installed on your machine, execute:

`$ gem install metabase_tarot`

With that, you will have access to the `tarot` command.
To create a Tarot environment and start using it, execute:

`$ tarot new [directory of your choice]`

To use your new Tarot environment, it is necessary to be inside its directory. Also, configure the pre-filled data in `tarot_spec.rb`:
- `url`: The URL of the Metabase application you want to connect to
- `session_expire_days`: The number of days it takes for your session to expire. If you don't know, leave the pre-filled value (Don't worry, using a wrong value here won't have serious consequences).
- `database_aliases`: It's a hash of aliases to use instead of the names of databases registered in Metabase. Useful to customize names when they are confusing or not standardized. The registered aliases will replace their original names. It is mandatory that the keys of this hash be symbols.

Having a configured environment, see in the sections below what you want to do.

### ⚝ How to record a `consultation`

A `consultation` in Tarot means a file that uses the utilities to communicate with Metabase and generate a results file. To create one, execute:

`$ tarot consultation [name of your consultation]`

A consultation file containing a template will be created in the `consultations` folder within your Tarot environment. The most important thing to know is that:
- **Only the part of the block passed to the `consultation` method needs to be modified in 99.99% of cases**
- `db('my db')` returns an object representing the database with the name (or alias) "my db" in Metabase.
- `db('my db').query!('select * bla bla bla')` executes the desired query and returns the parsed result.
- The return of the block passed to the `consultation` method will appear in the results file when you run the consultation.

To run the consultation, execute:

`$ tarot run [name of your consultation]`

### ⚝ How to open the console

Execute: `$ tarot console`

### ⚝ How to see the available databases

Execute: `$ tarot dbs`

### ⚝ How to see the available tables for a database

Execute: `$ tarot tables [name or alias of the bank]`

### ⚝ How to see the available columns for a table of a database

Execute: `$ tarot cols [name or alias of the bank] [name of the table]`

### ⚝ Notes

In every Tarot environment, a sensitive file called .secret_token is always created to store the user's token.

The `tarot new` creates:
- `tarot_spec.rb`
- `Gemfile` containing the dependency `metabase_tarot`
- `.gitignore` ignoring the `consultations/` folder and the `.secret_token` file

### Dependencies

- Ruby 3.0
