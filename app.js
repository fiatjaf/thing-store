/* global Elm */

const PouchDB = require('pouchdb-core')
  .plugin(require('pouchdb-adapter-idb'))
const debounce = require('debounce')

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
      k: doc.kv.map(kv => kv[0]),
      v: doc.kv.map(kv => kv[1]),
      calc: doc.kv.map(() => ''),
      focused: false
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

  let dCalc = debounce(([_id, idx, formula]) => {
    calc(formula)
      .then(res => {
        console.log(_id, idx, res)
        app.ports.gotCalcResult.send([_id, idx, res])
      })
      .catch(e => console.log(`error on calc(${formula})`, e))
  }, 1000)
  app.ports.calc.subscribe(dCalc)

  var queue = {}
  app.ports.queueRecord.subscribe(record => {
    queue[record.id] = {
      _id: record.id,
      kv: record.k.map((k, i) => [k, record.v[i]]),
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
