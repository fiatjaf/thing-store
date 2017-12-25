const cuid = require('cuid')

module.exports.id = function id (prf) {
  let c = cuid.slug()
  return prf + c.slice(0, -4) + c.slice(-2)
}

module.exports.debounceWithArgs = function debounceWithArgs (func, wait, arghasher) {
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

module.exports.toSimplified = function toSimplified (elmRecord) {
  var o = {}
  for (let i = 0; i < elmRecord.k.length; i++) {
    let k = elmRecord.k[i]
    if (k.length) {
      let calcValue = elmRecord.c[i]
      try {
        o[k] = JSON.parse(calcValue)
      } catch (e) {
        o[k] = calcValue
      }
    }
  }
  return o
}

module.exports.toPouch = function toPouch (elmRecord) {
  return {
    _id: elmRecord.id,
    kv: elmRecord.k.map((k, i) => [k, elmRecord.v[i]]),
    f: elmRecord.f.map(({linked}) => ({l: linked})),
    pos: elmRecord.pos,
    width: elmRecord.width,
    kind: elmRecord.kind
  }

  // still needs the _rev
}

module.exports.fromPouch = function fromPouch (doc) {
  return {
    id: doc._id,
    pos: doc.pos,
    width: doc.width || 180,
    kind: doc.kind === undefined ? null : doc.kind,
    k: doc.kv.map(kv => kv[0]),
    v: doc.kv.map(kv => kv[1]),
    c: doc.kv.map(kv => kv[1]),
    e: doc.kv.map(() => false),
    f: doc.f
      ? doc.f
        .map(({l}) => ({linked: l}))
      : doc.kv.map(() => ({linked: false})),
    focused: false
  }
}

module.exports.setAt = function setAt (object, path, value) {
  var o = object

  while (path.length > 1) {
    let k = path.shift()
    let nextO = o[k]
    if (!nextO) {
      nextO = {}
      o[k] = nextO
    }
    o = nextO
  }

  o[path[0]] = value
}

module.exports.getAt = function getAt (object, path) {
  var o = object

  while (path.length > 1) {
    o = o[path.shift()]
    if (!o) {
      o = {}
    }
  }

  return o[path[0]]
}

module.exports.hash = function hash (_id, idx) { return `${_id}¬${idx}` }
module.exports.unhash = function unhash (h) {
  let [_id, idxstr] = h.split('¬')
  return [_id, parseInt(idxstr)]
}
