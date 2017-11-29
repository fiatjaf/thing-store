const PouchDB = require('pouchdb-core')
  .plugin(require('pouchdb-adapter-idb'))
  .plugin(require('pouchdb-ensure'))

const db = new PouchDB('~')

module.exports.db = db

// ---

const Baobab = require('baobab')
const cuid = require('cuid')

let blankId = 'r-' + cuid.slug()

var tree = new Baobab({
  layout: {
    _id: 'layout',
    layout: []
  },
  draggable: false,

  blank: blankId,
  records: {
    [blankId]: {
      _id: blankId,
      kv: []
    }
  },

  focused: null,
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
  let currentBlank = tree.get('blank')

  for (let _id in e.data.currentData) {
    if (e.data.previousData[_id] !== e.data.currentData[_id]) {
      let doc = e.data.currentData[_id]

      // if this was the blank record, "unblank" it and create a new blank record
      if (doc._id === currentBlank && doc.kv.length > 0) {
        let nextBlankId = 'r-' + cuid.slug()

        tree.set(['records', nextBlankId], {
          _id: nextBlankId,
          kv: []
        })
        tree.commit()

        // only now that we've synchronously added the new blank record
        // we may set it as the current blank without triggering an infinite
        // update loop.
        tree.set('blank', nextBlankId)
      }

      // schedule record update on pouchdb
      tree.set(['pendingSaves', _id], doc)
    }
  }
})

// ---

module.exports.saveToPouch = function () {
  let byid = tree.get('pendingSaves')
  var docslist = Object.keys(byid)
    .map(_id => byid[_id])
    .map(doc => {
      delete doc.focused
      return doc
    })

  // always save current layout
  var ldoc = tree.get('layout')
  ldoc.layout = ldoc['live-layout'] || ldoc['layout']
  delete ldoc['live-layout']
  docslist.push(ldoc)

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
