const jq = require('jq-web/jq.wasm')

module.exports.calc = function (formula) {
  if (formula[0] === '=') {
    return jq({}, formula.slice(1))
  } else {
    return formula
  }
}
