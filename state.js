const PouchDB = require('pouchdb-core')
  .plugin(require('pouchdb-adapter-idb'))
  .plugin(require('pouchdb-ensure'))

const db = new PouchDB('~')

module.exports.db = db

// ---

const Baobab = require('baobab')

var tree = new Baobab({
  layout: {
    _id: 'layout',
    layout: []
  },
  draggable: false,
  records: {}
}, {
  immutable: false,
  persistent: true, // false?
  asynchronous: true, // false?
  monkeyBusiness: false,
  pure: false
})

module.exports.tree = tree

tree.select('records').on('update', e => {
  console.log('records updated', e.data.currentData)

  // schedule record update on pouchdb
})
tree.select('layout').on('update', e => {
  console.log('layout updated', e.data.currentData)

  // schedule layout update on pouchdb
})

// ---

db.allDocs({include_docs: true})
  .then(res => res.rows
    .map(r => r.doc)
    .map(doc => {
      if (doc._id === 'layout') {
        tree.set('layout', doc)
      } else if (doc._id.slice(0, 2) === 'r-') {
        tree.set(['records', doc._id], doc)
      }
    })
  )
