const cuid = require('cuid')

module.exports.id = function (prf) {
  let c = cuid.slug()
  return prf + c.slice(0, -4) + c.slice(-2)
}
