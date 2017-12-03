const jq = require('jq-web/jq.wasm')

module.exports.calcRecords = {}

module.exports.toSimplified = function (elmRecord) {
  var o = {}
  for (let i = 0; i < elmRecord.k.length; i++) {
    o[elmRecord.k[i]] = elmRecord.v[i]
  }
  return o
}

module.exports.calc = function (currId, formula) {
  var base = {}

  base._all = []
  for (let _id in module.exports.calcRecords) {
    let record = module.exports.calcRecords[_id]

    base[_id] = record

    base._all.push(record)

    for (let k in record) {
      base[k] = record[k]
    }
  }

  return Promise.resolve(JSON.stringify(jq(base, formula.slice(1))))
}
