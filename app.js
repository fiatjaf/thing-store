/* global Elm */

const PouchDB = require('pouchdb-core')
  .plugin(require('pouchdb-adapter-idb'))
  .plugin(require('pouchdb-ensure'))

const db = new PouchDB('~')

const { calc } = require('./calc')
const { id } = require('./helpers')

var app

db.allDocs({include_docs: true})
  .then(res => res.rows
    .map(r => r.doc)
    .map(doc => ({
      id: doc._id,
      pos: doc.pos,
      kv: doc.kv,
      calc: doc.kv.map(() => '')
    }))
  )
  .then(records => {
    app = Elm.Main.fullscreen({
      records: records,
      blank: id('r')
    })

    setupPorts(app)
  })
  .catch(e => console.log('initial docs loading failed', e))

function setupPorts (app) {
  app.ports.requestId.subscribe(() => {
    app.ports.gotId.send(id('r'))
  })

  app.ports.calc.subscribe(formula => {
    calc(formula)
      .then(res => {
        app.ports.gotCalcResult.send()
      })
      .catch(e => console.log(`error on calc(${formula})`, e))
  })

  var queue = {}
  app.ports.queueRecord.subscribe(record => {
    queue[record.id] = {
      _id: record.id,
      kv: record.kv,
      pos: record.pos
    }

    app.ports.gotPendingSaves.send(Object.keys(queue).length)
  })

  app.ports.saveToPouch.subscribe(() => {
    var docslist = Object.keys(queue)
      .map(_id => queue[_id])

    queue = {}

    return db.bulkDocs(docslist)
      .then(r => {
        console.log('saved queue')
        app.ports.gotSaveResult.send(`Saved ${docslist.length} records that were pending.`)
        app.ports.gotPendingSaves.send(Object.keys(queue).length)
      })
      .catch(e => {
        console.log('error saving queue', e)
        app.ports.gotSaveResult.send(`Error saving ${docslist.length} records.`)
      })
  })
}
