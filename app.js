const React = require('react')
const render = require('react-dom').render
const h = require('react-hyperscript')
const RGL = require('react-grid-layout')

class App extends React.Component {
  render () {
    return (
      h('div', [
        'x',
        h(RGL, {
          layout: [
            {i: 'a', x: 0, y: 0, w: 1, h: 2, static: true},
            {i: 'b', x: 1, y: 0, w: 3, h: 2, minW: 2, maxW: 4},
            {i: 'c', x: 4, y: 0, w: 1, h: 2}
          ]
        }, [
          h('div', {key: 'a'}, 'a'),
          h('div', {key: 'b'}, 'b'),
          h('div', {key: 'c'}, 'C')
        ])
      ])
    )
  }
}

render(
  h(App),
  document.getElementById('app'),
)
