const jq = require('jq-web/jq.wasm.js')

const { toSimplified, setAt } = require('./helpers')

let jqLoaded = new Promise(resolve => setTimeout(resolve, 5000))

var recordStore = module.exports.recordStore = {}

module.exports.calc = function calc (currentId, formula) {
  // build the object that will be passed to the formula
  var base = {}

  for (let _id in recordStore) {
    base[_id] = toSimplified(recordStore[_id])
  }

  let currentRecord = toSimplified(recordStore[currentId])
  for (let k in currentRecord) {
    base[k] = currentRecord[k]
  }

  // custom variables and functions
  let prelude = `
  `

  // execute and return
  return jqLoaded
    .then(() =>
      jq.raw(JSON.stringify(base), prelude + formula, ['-c'])
    )
    .catch(e => {
      console.log(JSON.stringify(base), prelude + formula)
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
    this.recordReferencesFrom = {}
    this.recordReferencesTo = {}

    this.rowReferencesFrom = {}
    this.rowReferencesTo = {}
  }

  * referencesTo (source_id, source_idx) {
    // references to this entire record made from other kv-rows
    for (let ref in this.recordReferencesTo[source_id]) {
      let [ref_id, ref_idx] = ref.split('¬')

      if (!(ref_id === source_id && ref_idx === source_idx.toString())) {
        yield [ref_id, parseInt(ref_idx)]
      }
    }

    // references specific to this kv-row from other kv-rows
    for (let ref in this.rowReferencesTo[`${source_id}¬${source_idx}`]) {
      let [ref_id, ref_idx] = ref.split('¬')
      yield [ref_id, parseInt(ref_idx)]
    }
  }

  clearReferencesFrom (source_id, source_idx) {
    for (let ref_id in this.recordReferencesFrom[`${source_id}¬${source_idx}`]) {
      delete this.recordReferencesFrom[`${source_id}¬${source_idx}`]
      delete this.recordReferencesTo[ref_id][`${source_id}¬${source_idx}`]
    }

    for (let ref in this.rowReferencesFrom[`${source_id}¬${source_idx}`]) {
      delete this.rowReferencesFrom[source_id]
      delete this.rowReferencesTo[ref][`${source_id}¬${source_idx}`]
    }
  }

  setReferencesFrom (_id, idx, formula) {
    let source = `${_id}¬${idx}`

    formula.replace(
      /(^| |\W)\.(r\w{5}\b)(\.(\w+)|\["(\w+)"\])?/g,
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

    // always reference itself -- so when a kv pair change, recalc all others
    setAt(this.recordReferencesTo, [_id, source])
    setAt(this.recordReferencesFrom, [source, _id])
  }
}

module.exports.depGraph = new DepGraph()

module.exports.view = function view (code) {
  return {}
}
