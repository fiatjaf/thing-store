const PouchDB = require('pouchdb-core')
  .plugin(require('pouchdb-adapter-idb'))
  .plugin(require('pouchdb-ensure'))

module.exports.db = new PouchDB('~')

const { Record } = require('immutable')

module.exports.KV = Record({k: '', v: ''})
