const cuid = require('cuid')

module.exports.id = function (prf) {
  let c = cuid.slug()
  return prf + c.slice(0, -4) + c.slice(-2)
}

module.exports.debounceWithArgs = function (func, wait, arghasher) {
  var cache = {}

  function call (key, args) {
    clearTimeout(cache[key])
    func.apply(this, args)
  }

  var debounced = function () {
    let key = arghasher(arguments)
    clearTimeout(cache[key])
    cache[key] = setTimeout(call.bind(this, key, arguments), wait)
  }

  return debounced
}
