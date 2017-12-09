const jq = require('jq-web/jq.wasm.js')

const { toSimplified, setAt } = require('./helpers')

let jqLoaded = new Promise(resolve => setTimeout(resolve, 5000))

var recordStore = module.exports.recordStore = {}

module.exports.calc = function calc (currId, formula) {
  // build the object that will be passed to the formula
  var base = {}
  var all = []

  for (let _id in recordStore) {
    let record = recordStore[_id]

    let srecord = toSimplified(record)
    base[_id] = srecord
    all.push(srecord)

    for (let k in srecord) {
      base[k] = srecord[k]
    }
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
    for (let ref in this.recordReferencesTo[source_id]) {
      let [ref_id, ref_idx] = ref.split('¬')
      yield [ref_id, parseInt(ref_idx)]
    }

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
        if (target_id === _id) {
          throw new Error('circular reference')
        }

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
