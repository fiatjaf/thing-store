const jq = require('jq-web/jq.wasm')
const Graph = require('graph.js/dist/graph.full.js')
const concat = require('concat-iterator')

function toSimplified (elmRecord) {
  var o = {}
  for (let i = 0; i < elmRecord.k.length; i++) {
    let k = elmRecord.k[i]
    if (k.length) {
      o[k] = elmRecord.v[i]
    }
  }
  return o
}

module.exports.calc = function (currId, formula) {
  // build the object that will be passed to the formula
  var base = {}

  base._all = []
  for (let [_id, record] of depGraph.vertices()) {
    if (_id === ALL) continue

    let srecord = toSimplified(record)
    base[_id] = srecord
    base._all.push(srecord)

    for (let k in srecord) {
      base[k] = srecord[k]
    }
  }

  // execute and return
  let res = jq(base, formula)
  return Promise.resolve(res)
}

class DepGraph extends Graph {
  constructor () {
    super()

    this.addVertex(ALL, {})
  }

  refs (_id) {
    try {
      return this.verticesFrom(_id)
    } catch (e) {
      return []
    }
  }

  dependents (_id) {
    try {
      return concat(
        this.verticesTo(_id),
        this.verticesTo(ALL)
      )
    } catch (e) {
      return []
    }
  }

  cleanRefs (_id) {
    for (let [refId] of this.refs(_id)) {
      this.removeEdge(_id, refId)
    }
  }

  insertRefs (_id, formula) {
    if (/(^| )\._all\b/.exec(formula)) {
      this.addEdge(_id, ALL)
    }

    formula.replace(/(^| )\.(r\w{5})\b/g, (m, _, ref) => {
      this.addEdge(_id, ref)
    })
  }
}

const ALL = module.exports.ALL = '$$_all$$'
var depGraph = module.exports.depGraph = new DepGraph()
