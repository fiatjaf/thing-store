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

  records: {},

  formulaEditing: null,

  pendingSaves: {},
  hasPending: Baobab.monkey({
    cursors: {
      pendingSaves: ['pendingSaves']
    },
    get: ({pendingSaves}) => {
      return Object.keys(pendingSaves).length > 0
    }
  })
}, {
  immutable: false,
  persistent: true, // false?
  asynchronous: true, // false?
  monkeyBusiness: true,
  pure: false
})

module.exports.tree = tree

// tree.on('write', function (e) {
//   console.log('write', e)
// })

tree.select('records').on('update', e => {
  // schedule record update on pouchdb
  for (let _id in e.data.currentData) {
    if (e.data.previousData[_id] !== e.data.currentData[_id]) {
      tree.set(['pendingSaves', _id], e.data.currentData[_id])
    }
  }
})

// ---

module.exports.saveToPouch = function () {
  let byid = tree.get('pendingSaves')
  var docslist = Object.keys(byid).map(_id => byid[_id])

  // always save current layout
  docslist.push(tree.get('layout'))

  return db.bulkDocs(docslist)
    .then(r => {
      tree.set('pendingSaves', {})
      return r
    })
}

db.allDocs({include_docs: true})
  .then(res => res.rows
    .map(r => r.doc)
    .map(doc => {
      if (doc._id === 'layout') {
        tree.set('layout', doc)
      } else if (doc._id.slice(0, 2) === 'r-') {
        tree.set(['records', doc._id], doc)
      }
      tree.commit()
      tree.set('pendingSaves', {})
    })
  )
