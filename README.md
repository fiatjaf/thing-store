**thing-store** is an pure-client-side app you can use to keep arbitrary collections of records of arbitrary structure or declare calculations between values.

Each record can have any number of fields of any scalar JSON type (or raw JSON directly), links to other records or formulas.

Links to other records are just strings in the format `@<record-id>` along with a search feature so you can link to other records by searching their keys and values instead of writing their ids manually.

Formulas are backed by [jq](https://stedolan.github.io/jq/manual/) and can access all values inside the same record (using the dot notation -- `.<key>`), other records (using their id as variables -- `$<record-id>`), or direct access to other records through linked fields (if `.abc` is a link to the record `xyz`, you access the key `.mno` on that record by writing `.a | link | .mno` -- which is a just a shortcut for `$xyz.mno` that helps when you have a template with formulas).

Formulas can also use the special function `kind(<name>)` which takes the name of a kind defined in the settings menu and returns an array of all records in that kind.

Persistency is achieved through [PouchDB](https://pouchdb.com/).

This is a work in progress. Many features are going to be implemented still. Please leave your feedback as an issue or as a comment in the last commit of this repo.

There's a deployed demo version at https://abstracted-flavor.surge.sh/

![](resources/pikachu-the-pikachu.gif)
![](resources/raichu-evolution.gif)
