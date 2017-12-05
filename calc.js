const jq = require('jq-web/jq.wasm')
const Graph = require('graph.js/dist/graph.full.js')
const concat = require('concat-iterator')

function toSimplified (elmRecord) {
  var o = {}
  for (let i = 0; i < elmRecord.k.length; i++) {
    let k = elmRecord.k[i]
    if (k.length) {
      let calcValue = elmRecord.calc[i]
      try {
        o[k] = JSON.parse(calcValue)
      } catch (e) {
        o[k] = calcValue
      }
    }
  }
  return o
}

module.exports.calc = function (currId, formula) {
  // build the object that will be passed to the formula
  var base = {}
  var all = []

  for (let [_id, record] of depGraph.vertices()) {
    if (_id === ALL) continue

    let srecord = toSimplified(record)
    base[_id] = srecord
    all.push(srecord)

    for (let k in srecord) {
      base[k] = srecord[k]
    }
  }

  // custom variables and functions
  let prelude = `
${JSON.stringify(all)} as $all |
def find(expr): $all | map(select(expr)) | .[0];
def filter(expr): $all | map(select(expr));
  `

  // execute and return
  try {
    let res = jq.raw(JSON.stringify(base), prelude + formula, ['-c'])
    return Promise.resolve(res)
  } catch (e) {
    console.log(JSON.stringify(base), prelude + formula)
    return Promise.reject(e)
  }
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
    if (/(^| )\$all\b/.exec(formula)) {
      this.addEdge(_id, ALL)
    }

    formula.replace(/(^| )\.(r\w{5})\b/g, (m, _, ref) => {
      this.addEdge(_id, ref)
    })
  }
}

const ALL = module.exports.ALL = '$$_all$$'
var depGraph = module.exports.depGraph = new DepGraph()
