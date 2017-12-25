/* global Elm */

const PouchDB = require('pouchdb-core')
const IDB = require('pouchdb-adapter-idb')
const pSeries = require('p-series')

const {
  calc, recalc, depGraph, recordStore,
  kindStore, settingsStore, view
} = require('./calc')
const { id, debounceWithArgs, toPouch, hash, unhash, fromPouch } = require('./helpers')

PouchDB.plugin(IDB)
var db = new PouchDB('~')
var changes

var app = Elm.Main.fullscreen()

var revCache = {}

const startListening = listen.bind(null, 0)
const restartListening = listen.bind(null, 'now')
function listen (since) {
  changes = db.changes({
    since: since,
    live: true,
    include_docs: true
  })
    .on('change', gotChange)
    .on('error', e => {
      console.log('error on changes')
      app.ports.notify.send(`error on the changes listener: ${e.message}`)
    })
}

startListening()

function gotChange (change) {
  let doc = change.doc

  revCache[doc._id] = doc._rev

  if (doc._id === 'config') {
    let config = {kinds: doc.kinds}
    settingsStore.config = config
    app.ports.gotUpdatedConfig.send(config)
    return
  }

  let record = fromPouch(doc)

  recordStore[record.id] = record
  if (record.kind) {
    kindStore[record.kind] = kindStore[record.kind] || {}
    kindStore[record.kind][record.id] = true
  }

  if (doc._deleted) {
    app.ports.gotDeletedRecord.send(record.id)
  } else {
    app.ports.gotUpdatedRecord.send(record)
  }

  for (let idx = 0; idx < record.k.length; idx++) {
    preCalc(record.id, idx, record.v[idx])
  }

  // calculating just the first value is enough to recalc all the others
  actualCalc(record.id, 0)
}

function preCalc (_id, idx, value) {
  value = value.trim()
  recordStore[_id].v[idx] = value

  depGraph.clearReferencesFrom(_id, idx)

  if (value[0] === '=') {
    let formula = value.slice(1)
    depGraph.gatherReferencesFrom(_id, idx, formula)
  } else {
    depGraph.gatherLinks(_id, idx, value)
  }
}

function actualCalc (_id, idx) {
  var calcs = []
  for (let h of recalc(_id, idx)) {
    let [_id, idx] = unhash(h)
    console.log('next_calc', _id, idx)

    calcs.push(() => {
      console.log('calculating', _id, idx)
      calc(_id, recordStore[_id].v[idx])
        .then(res => {
          if (res) {
            app.ports.gotCalcResult.send([_id, idx, res])
            recordStore[_id].c[idx] = JSON.parse(res)
          } else {
            recordStore[_id].c[idx] = recordStore[_id].v[idx]
          }
        })
    })
  }

  return pSeries(calcs)
    .catch(e => {
      if (e.message === 'circular reference') {
        console.log(`circular reference on ${_id}:${idx}`)
      } else {
        console.log(e)
      }
    })
    .catch(e => console.log('error', e))
}

function changedValue ([_id, idx, value]) {
  preCalc(_id, idx, value)
  actualCalc(_id, idx)
}

app.ports.changedValue.subscribe(
  debounceWithArgs(changedValue, 2000, args => hash(args[0][0], args[0][1]))
)

function runView (code) {
  view(code)
    .then(recordlist => {
      app.ports.replaceRecords.send(recordlist)
    })
    .catch(e => console.log('failed running view', e))
}

app.ports.runView.subscribe(
  debounceWithArgs(runView, 2000, args => args[0][0])
)

var queue = {}
app.ports.queueSaveRecord.subscribe(record => {
  // this must be updated
  queue[record.id] = true

  app.ports.gotPendingSaves.send(Object.keys(queue).length)

  // update the record in the canonical store
  recordStore[record.id] = record
})

app.ports.changedKind.subscribe(([_id, prev, curr]) => {
  if (prev) {
    delete kindStore[prev][_id]

    let kindName = settingsStore.config.kinds[prev].name
    for (let [did, didx] of depGraph.referencesToKind(kindName)) {
      let v = recordStore[did].v[didx]
      changedValue([did, didx, v])
    }
  }
  if (curr) {
    kindStore[curr] = kindStore[curr] || {}
    kindStore[curr][_id] = true

    let kindName = settingsStore.config.kinds[curr].name
    for (let [did, didx] of depGraph.referencesToKind(kindName)) {
      let v = recordStore[did].v[didx]
      changedValue([did, didx, v])
    }
  }
})

app.ports.saveToPouch.subscribe(() => {
  let willSave = Object.keys(queue).length

  var docslist = Object.keys(queue)
    .map(_id => {
      let doc = toPouch(recordStore[_id])
      doc._rev = revCache[_id]
      return doc
    })

  changes.cancel() // stop listening here and start again after the save is done

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

      let nsaved = willSave - Object.keys(queue).length
      app.ports.notify.send(
        `Saved ${nsaved} records.` +
        (nsaved < willSave ? ` ${willSave - nsaved} remaining.` : '')
      )
      app.ports.gotPendingSaves.send(Object.keys(queue).length)
    })
    .catch(e => {
      console.log('error saving queue', e)
      app.ports.notify.send(`Error saving ${docslist.length} records.`)
    })
    .then(() => {
      restartListening()
    })
})

app.ports.requestId.subscribe(() => { app.ports.gotId.send(id('r')) })

app.ports.changedConfig.subscribe(config => {
  settingsStore.config = config
})

app.ports.saveConfig.subscribe(config => {
  let doc = {
    _id: 'config',
    _rev: revCache['config'],
    kinds: config.kinds
  }

  db.put(doc)
    .then(res => {
      revCache['config'] = res.rev
      console.log('saved config', res)
      app.ports.notify.send('Settings saved.')
    })
    .catch(e => {
      console.log('error saving config', e)
      app.ports.notify.send('Error saving settings.')
    })
})
