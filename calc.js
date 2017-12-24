const jq = require('jq-web/jq.wasm.js')

const { toSimplified, hash, unhash, getAt, setAt } = require('./helpers')

let jqLoaded = new Promise(resolve => setTimeout(resolve, 5000))

var recordStore = module.exports.recordStore = {}
var kindStore = module.exports.kindStore = {}
var settingsStore = module.exports.settingsStore = {}

module.exports.calc = function calc (currentId, value) {
  if (value[0] !== '=') return Promise.resolve()
  let formula = value.slice(1)

  // the object that will be passed to the formula
  let current = recordStore[currentId]
  var currentRecord = toSimplified(current)

  // all the other records, custom variables and functions
  var prelude = ''
  for (let _id in recordStore) {
    prelude += `${JSON.stringify(toSimplified(recordStore[_id]))} as $${_id} | `
  }

  // a function kind(k) to fetch a list of records from the given kind
  let idsByKindName = '{' +
    Object.keys(kindStore)
      .map(kind => {
        let name = settingsStore.config.kinds[kind].name
        return `${name}:[` +
          Object.keys(kindStore[kind]).map(_id => '$' + _id) +
         ']'
      })
      .join(',') +
    '}'
  prelude += `def kind(k): ${idsByKindName} | .[k]; `

  // a function 'link()' to fetch linked records
  var variablesById = '{' +
    current.v
      .map(v => (v.slice(0, 2) === '@r') ? `"${v}": $${v.slice(1)}` : null)
      .filter(x => x)
      .join(',') +
    '}'
  prelude += `def link: ${variablesById}[.]; `

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

    this.linksFrom = {}
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
    let source = `${source_id}¬${source_idx}`

    for (let kind in this.kindReferencesFrom[source]) {
      delete this.kindReferencesFrom[source]
      delete this.kindReferencesTo[kind][source]
    }

    for (let ref_id in this.recordReferencesFrom[source]) {
      delete this.recordReferencesFrom[source]
      delete this.recordReferencesTo[ref_id][source]
    }

    for (let ref in this.rowReferencesFrom[source]) {
      delete this.rowReferencesFrom[source]
      delete this.rowReferencesTo[ref][source]
    }
  }

  gatherLinks (_id, idx, value) {
    setAt(this.linksFrom, [_id, idx], {})
    if (value.slice(0, 2) === '@r') {
      setAt(this.linksFrom, [_id, idx, value.slice(1)], true)
    }
  }

  gatherReferencesFrom (_id, idx, formula) {
    let source = `${_id}¬${idx}`

    formula.replace(/\bkind\("([^"]+)"\)/g, (fullmatch, kind) => {
      setAt(this.kindReferencesTo, [kind, source], true)
      setAt(this.kindReferencesFrom, [source, kind], true)
    })

    if (formula.match(/\| *link\b/)) {
      console.log('formula match', formula)
      // if there any call to the link function, make this row depend on all
      // other records linked by this entire record
      let by_idx = getAt(this.linksFrom, [_id])
      for (let idx in by_idx) {
        for (let link_id in by_idx[idx]) {
          setAt(this.recordReferencesTo, [link_id, source], true)
          setAt(this.recordReferencesFrom, [source, link_id], true)
        }
      }
    }

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

var depGraph = module.exports.depGraph = new DepGraph()

// returns a list (actually a Set) of rows that must be recalc'ed, in order
module.exports.recalc = recalc
function recalc (from_id, from_idx, prev_list = new Set()) {
  var local = new Set()
  var list = new Set(prev_list)

  // the changed row itself
  console.log('here', from_id, from_idx)
  let h = hash(from_id, from_idx)
  local.add(h)
  list.delete(h)
  list.add(h)

  // internal references (all other rows from this same record)
  let current = recordStore[from_id]
  for (let other_idx = 0; other_idx < current.k.length; other_idx++) {
    if (other_idx === from_idx) continue
    if (current.v[other_idx][0] !== '=') continue

    console.log('local', from_id, other_idx)
    let h = hash(from_id, other_idx)
    local.add(h)
    list.delete(h)
    list.add(h)
  }

  var final_list = new Set(list)

  // now, from the initial row and each affected local, search external refs
  for (let h of local) {
    let [l_id, l_idx] = unhash(h)

    for (let [ext_id, ext_idx] of depGraph.referencesTo(l_id, l_idx)) {
      console.log('external', ext_id, ext_idx)

      if (prev_list.has(hash(ext_id, ext_idx))) {
        throw new Error('circular reference')
      }

      for (let h of recalc(ext_id, ext_idx, list)) {
        final_list.delete(h)
        final_list.add(h)
      }
    }
  }

  return final_list
}

module.exports.view = function view (code) {
  return {}
}
