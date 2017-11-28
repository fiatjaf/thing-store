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

tree.select('records').on('update', e => {
  console.log('records updated', e.data.currentData)

  // schedule record update on pouchdb
  for (let _id in e.data.currentData) {
    if (e.data.previousData[_id] !== e.data.currentData[_id]) {
      tree.set(['pendingSaves', _id], e.data.currentData[_id])
    }
  }
})
tree.select('layout').on('update', e => {
  console.log('layout updated', e.data.currentData)
  // since the layout changes too much and may set up an infinite recursion of
  // actions, we will fetch its current state on save time.
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
