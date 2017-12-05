/* global Elm */

const PouchDB = require('pouchdb-core')
  .plugin(require('pouchdb-adapter-idb'))
const debounce = require('debounce')

const db = new PouchDB('~')

const { calc, depGraph } = require('./calc')
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

    // prepare records to use in formulas
    records.forEach(record => {
      depGraph.addVertex(record.id, record)
    })

    setupPorts(app)
  })
  .catch(e => console.log('initial docs loading failed', e))

function setupPorts (app) {
  app.ports.requestId.subscribe(() => {
    app.ports.gotId.send(id('r'))
  })

  function changedValue ([_id, idx, key, value]) {
    console.log('changed value', _id, idx, key, value)
    depGraph.cleanRefs(_id)

    var waitCalc
    if (value[0] === '=') {
      let formula = value.slice(1)

      depGraph.insertRefs(_id, formula)

      waitCalc = calc(_id, formula)
        .then((res) => {
          console.log(_id, idx, res)
          app.ports.gotCalcResult.send([_id, idx, res])

          depGraph.vertexValue(_id)[key] = JSON.parse(res)
        })
        .catch(e => console.log(`error on calc(${value})`, e))
    } else {
      depGraph.vertexValue(_id)[key] = value
      waitCalc = Promise.resolve()
    }

    waitCalc
      .then(() => {
        for (let [did, record] of depGraph.dependents(_id)) {
          for (let i = 0; i < record.k.length; i++) {
            changedValue([did, i, record.k[i], record.v[i]])
          }
        }
      })
      .catch(e => console.log('error', e))
  }

  app.ports.changedValue.subscribe(debounce(changedValue, 1000))

  var queue = {}
  app.ports.queueRecord.subscribe(record => {
    queue[record.id] = {
      _id: record.id,
      kv: record.k.map((k, i) => [k, record.v[i]]),
      pos: record.pos
    }

    app.ports.gotPendingSaves.send(Object.keys(queue).length)

    // prepare record to use in formulas
    depGraph.addVertex(record.id, record)
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
