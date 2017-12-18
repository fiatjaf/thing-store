const jq = require('jq-web/jq.wasm.js')

const { toSimplified, setAt } = require('./helpers')

let jqLoaded = new Promise(resolve => setTimeout(resolve, 5000))

var recordStore = module.exports.recordStore = {}
var kindStore = module.exports.kindStore = {}
var settingsStore = module.exports.settingsStore = {}

module.exports.calc = function calc (currentId, formula) {
  // the object that will be passed to the formula
  let currentRecord = toSimplified(recordStore[currentId])

  // all the other records, custom variables and functions
  var prelude = ''
  for (let _id in recordStore) {
    prelude += `${JSON.stringify(toSimplified(recordStore[_id]))} as $${_id} | `
  }

  let idsByKindName = '{' +
    Object.keys(kindStore)
      .map(kind => {
        let name = settingsStore.config.kinds[kind].name
        return `"${name}":[` +
          Object.keys(kindStore[kind]).map(_id => '$' + _id) +
         ']'
      }) +
    '}'
  prelude += `def kind(k): ${idsByKindName} | .[k]; `

  // execute and return
  formula = formula || 'null'

  return jqLoaded
    .then(() =>
      jq.raw(JSON.stringify(currentRecord), prelude + formula, ['-c'])
    )
    .catch(e => {
      console.log(JSON.stringify(currentRecord), prelude + formula)
      if (e.message && e.message.slice(0, 10) === 'jq: error ') {
        e.message = e.message.slice(10)
        e.message = e.message.slice(0, 16) === '(at <stdin>:0): '
          ? e.message.slice(16)
          : e.message
      }
      throw e
    })
}

class DepGraph {
  constructor () {
    this.kindReferencesFrom = {}
    this.kindReferencesTo = {}

    this.recordReferencesFrom = {}
    this.recordReferencesTo = {}

    this.rowReferencesFrom = {}
    this.rowReferencesTo = {}
  }

  * referencesToKind (kindName) {
    for (let ref in this.kindReferencesTo[kindName]) {
      let [ref_id, ref_idx] = ref.split('¬')
      yield [ref_id, parseInt(ref_idx)]
    }
  }

  * referencesTo (source_id, source_idx) {
    // references to this kind made from other kv-rows
    let source_kind = recordStore[source_id].kind
    if (source_kind) {
      let kindName = settingsStore.config.kinds[source_kind].name
      if (kindName) {
        yield * this.referencesToKind(kindName)
      }
    }

    // references to this entire record made from other kv-rows
    for (let ref in this.recordReferencesTo[source_id]) {
      let [ref_id, ref_idx] = ref.split('¬')
      yield [ref_id, parseInt(ref_idx)]
    }

    // references specific to this kv-row from other kv-rows
    for (let ref in this.rowReferencesTo[`${source_id}¬${source_idx}`]) {
      let [ref_id, ref_idx] = ref.split('¬')
      yield [ref_id, parseInt(ref_idx)]
    }
  }

  clearReferencesFrom (source_id, source_idx) {
    for (let kind in this.kindReferencesFrom[`${source_id}¬${source_idx}`]) {
      delete this.kindReferencesFrom[`${source_id}¬${source_idx}`]
      delete this.kindReferencesTo[kind][`${source_id}¬${source_idx}`]
    }

    for (let ref_id in this.recordReferencesFrom[`${source_id}¬${source_idx}`]) {
      delete this.recordReferencesFrom[`${source_id}¬${source_idx}`]
      delete this.recordReferencesTo[ref_id][`${source_id}¬${source_idx}`]
    }

    for (let ref in this.rowReferencesFrom[`${source_id}¬${source_idx}`]) {
      delete this.rowReferencesFrom[source_id]
      delete this.rowReferencesTo[ref][`${source_id}¬${source_idx}`]
    }
  }

  gatherReferencesFrom (_id, idx, formula) {
    let source = `${_id}¬${idx}`

    formula.replace(/kind\("([^"]+)"\)/g, (fullmatch, kind) => {
      setAt(this.kindReferencesTo, [kind, source], true)
      setAt(this.kindReferencesFrom, [source, kind], true)
    })

    formula.replace(
      /(^| |\W)\$(r\w{5}\b)(\.(\w+)|\["(\w+)"\])?/g,
      (fullmatch, _, target_id, key2, key1) => {
        let target_idx = recordStore[target_id].k.indexOf(key1 || key2)
        if (target_idx !== -1) {
          setAt(this.rowReferencesTo, [`${target_id}¬${target_idx}`, source], true)
          setAt(this.rowReferencesFrom, [source, `${target_id}¬${target_idx}`], true)
        } else {
          // key not found, depend on the entire record
          setAt(this.recordReferencesTo, [target_id, source], true)
          setAt(this.recordReferencesFrom, [source, target_id], true)
        }
      }
    )
  }
}

module.exports.depGraph = new DepGraph()

module.exports.view = function view (code) {
  return {}
}
