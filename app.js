/* global Elm */

const PouchDB = require('pouchdb-core')
const IDB = require('pouchdb-adapter-idb')

const { calc, depGraph, recordStore } = require('./calc')
const { id, debounceWithArgs, toPouch } = require('./helpers')

PouchDB.plugin(IDB)
const db = new PouchDB('~')

var app

var revCache = {}

db.allDocs({include_docs: true})
  .then(res => res.rows
    .map(r => console.log(r) || r)
    .map(r => r.doc)
    .map(doc => {
      revCache[doc._id] = doc._rev

      return {
        id: doc._id,
        pos: doc.pos,
        k: doc.kv.map(kv => kv[0]),
        v: doc.kv.map(kv => kv[1]),
        c: doc.kv.map(kv => kv[1]),
        e: doc.kv.map(() => false),
        focused: false
      }
    })
  )
  .then(records => {
    app = Elm.Main.fullscreen({
      records: records,
      blank: id('r')
    })

    // prepare records to use in formulas
    records.forEach(record => {
      recordStore[record.id] = record
    })

    setupPorts(app)
  })
  .catch(e => console.log('initial docs loading failed', e))

function setupPorts (app) {
  app.ports.requestId.subscribe(() => {
    app.ports.gotId.send(id('r'))
  })

  function changedValue ([_id, idx, value]) {
    depGraph.clearReferencesFrom(_id, idx)
    recordStore[_id].v[idx] = value

    var waitCalc
    if (value[0] === '=') {
      let formula = value.slice(1)

      try {
        depGraph.setReferencesFrom(_id, idx, formula)

        waitCalc = calc(_id, formula)
          .then((res) => {
            console.log(_id, idx, res)
            app.ports.gotCalcResult.send([_id, idx, res])
            recordStore[_id].c[idx] = JSON.parse(res)
          })
          .catch(e => {
            console.log(`error on calc(${value})`, e)
            app.ports.gotCalcError.send([_id, idx, e.message])
            recordStore[_id].c[idx] = null
          })
      } catch (e) {
        if (e.message === 'circular reference') {
          console.log(`circular reference on ${_id}:${idx}: ${value}`)
          app.ports.gotCalcError.send([_id, idx, e.message])
          recordStore[_id].c[idx] = null
        }
        waitCalc = Promise.reject(e)
      }
    } else {
      recordStore[_id].c[idx] = value
      waitCalc = Promise.resolve()
    }

    waitCalc
      .then(() => {
        for (let [did, didx] of depGraph.referencesTo(_id, idx)) {
          let v = recordStore[did].v[didx]
          changedValue([did, didx, v])
        }
      })
      .catch(e => console.log('error', e))
  }

  app.ports.changedValue.subscribe(
    debounceWithArgs(changedValue, 2000, args => args[0][0] + '¬' + args[0][1])
  )

  var queue = {}
  app.ports.queueRecord.subscribe(record => {
    // this must be updated
    queue[record.id] = true

    app.ports.gotPendingSaves.send(Object.keys(queue).length)

    // update the record in the canonical store
    recordStore[record.id] = record
  })

  app.ports.saveToPouch.subscribe(() => {
    let willSave = Object.keys(queue).length

    var docslist = Object.keys(queue)
      .map(_id => {
        let doc = toPouch(recordStore[_id])
        doc._rev = revCache[_id]
        return doc
      })

    return db.bulkDocs(docslist)
      .then(res => {
        console.log('saved queue', res)
        for (let i = 0; i < res.length; i++) {
          let r = res[i]
          if (r.ok) {
            revCache[r.id] = r.rev
            delete queue[r.id]
          }
        }

        let nsaved = Object.keys(queue).length - willSave

        app.ports.notify.send(
          `Saved ${nsaved} records.` +
          nsaved < willSave ? ` ${willSave - nsaved} remaining.` : ''
        )
        app.ports.gotPendingSaves.send(Object.keys(queue).length)
      })
      .catch(e => {
        console.log('error saving queue', e)
        app.ports.notify.send(`Error saving ${docslist.length} records.`)
      })
  })
}
