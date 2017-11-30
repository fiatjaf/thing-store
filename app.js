const React = require('react')
const render = require('react-dom').render
const h = require('react-hyperscript')
const styled = require('styled-components').default
const hashbow = require('hashbow')
const RGL = require('react-grid-layout')
const { getLayoutItem, compactItem } = require('react-grid-layout/build/utils')

const ReactGridLayout = RGL.WidthProvider(RGL)

const { tree, saveToPouch } = require('./state')
const { calc } = require('./calc')

class App extends React.Component {
  constructor () {
    super()

    this.recordsCursor = tree.select('records')
    this.draggableCursor = tree.select('draggable')
    this.hasPendingCursor = tree.select('hasPending')

    this.baseLayout = {
      minW: 3,
      w: 3,
      minH: 1
    }
  }

  componentDidMount () {
    this.recordsCursor.on('update', () => { this.forceUpdate() })
    this.draggableCursor.on('update', () => { this.forceUpdate() })
    this.hasPendingCursor.on('update', () => { this.forceUpdate() })
  }

  componentWillUnmount () {
    this.recordsCursor.release()
    this.draggableCursor.release()
    this.hasPendingCursor.release()
  }

  render () {
    let {layout, draggable, records, hasPending} = tree.project({
      layout: ['layout', 'layout'],
      draggable: ['draggable'],
      records: ['records'],
      hasPending: ['hasPending']
    })

    return (
      h('div', [
        h('.columns.is-mobile', [
          h('.column', 'data at "~"'),
          h('.column', [
            h('button.button.is-info', {
              onClick: () => tree.set('draggable', !draggable)
            }, draggable ? 'done' : 'rearrange')
          ]),
          h('.column', [
            h('button.button.is-success', {
              onClick: () => saveToPouch()
                .then(r => console.log('saved to pouch', r))
                .catch(e => console.log('failed saving to pouch', e)),
              disabled: !hasPending
            }, hasPending ? 'Save' : 'Everything saved already')
          ])
        ]),
        h(ReactGridLayout, {
          isDraggable: draggable,
          items: 40,
          rowHeight: 28,
          cols: 36,
          onLayoutChange: l => tree.set(['layout', 'live-layout'], l),
          containerPadding: [0, 0],
          margin: [0, 0],
          compactType: null,
          autoSize: false,
          layout: layout
        }, Object.keys(records)
          .map(_id => records[_id])
          .map(record => {
            let layoutItem = getLayoutItem(layout, record._id)

            let height = record.kv.length + 1
            let actualLayout = Object.assign(
              {x: 33, y: 12, i: record._id},
              this.baseLayout,
              layoutItem,
              {h: height, maxH: height}
            )

            return h('div', {
              key: record._id,
              'data-grid': layoutItem
                ? actualLayout
                : compactItem(layout, actualLayout, 'horizontal', 36, layout)
            }, [
              h(Document, {_id: record._id})
            ])
          })
        )
      ])
    )
  }
}

const docDiv = styled.div`A
  height: 100%;
  overflow: hidden;
  border: 2px solid ${props => hashbow(props.id)};

  table {
    background-color: ${props => props.focused ? 'white' : 'papayawhip'};
    width: 100%;
    margin: 0;
    border-collapse: collapse;
    border-spacing: 0;
  }

  td, th {
    height: 28px;
    border: 1px solid #dbdbdb;
  }

  th {
    width: 39%;
    max-width: 100px;
    position: relative;
    background-color: ${props => props.focused ? '#f39d5d' : '#f6f1f6'};

    &:after {
      content: ": ";
      position: absolute;
      right: 0;
    }

    input {
      text-align: right;
      padding-right: 6px;

      &:focus {
        background-color: #ffe8d7;
      }
    }
  }

  td {
    input {
      padding-left: 5px;

      &:focus {
        background-color: #def6ff;
      }
    }
  }

  input {
    width: 100%;
    height: 100%;
    border: none;
    font-family: monospace;
    background-color: inherit;
  }
`

class Document extends React.Component {
  constructor (props) {
    super(props)

    this.cursor = tree.select(['records', this.props._id])
    this.calc = tree.select(['calcResults', this.props._id])
    this.focused = tree.select('focused')
  }

  componentDidMount () {
    this.cursor.on('update', e => {
      console.log('record updated: ' + this.props._id, e.data.currentData)
      this.forceUpdate()
    })

    this.calc.on('update', e => {
      console.log('calc results updated: ' + this.props._id, e.data.currentData)
      this.forceUpdate()
    })

    this.focused.on('update', e => {
      console.log(this.props._id + ' focused state change', e.data.currentData)
      if (this.props._id === e.data.currentData ||
          this.props._id === e.data.previousData) {
        this.forceUpdate()

        // recalc formulas on focus out
        if (e.data.currentData !== this.props._id) {
          this.cursor.get().kv.forEach(([_, formula], i) => {
            calc(formula)
              .then(result => this.calc.set(i, result))
              .catch(e => console.log(`failed to calc(${formula})`, e))
          })
        }
      }
    })
  }

  componentWillUnmount () {
    this.cursor.tree && this.cursor.release()
    this.calc.tree && this.calc.release()
  }

  shouldComponentUpdate (nextProps) {
    return this.props._id !== nextProps._id
  }

  render () {
    let record = this.cursor.get()
    let focused = this.focused.get() === record._id
    let calcResults = this.calc.get()

    return (
      h(docDiv, {
        id: record._id,
        focused: focused,
        onMouseDown: e => {
          // normally, clicking here should "focus" this record
          if (!focused) tree.set('focused', record._id)
        }
      }, [
        h('table', {title: record._id}, [
          h('tbody', {}, record
            .kv
            .concat([['', '']])
            .map(([k, v], i) =>
              h('tr', {key: i, id: k}, [
                h('th', [
                  h('input.k', {
                    value: k,
                    onChange: e => {
                      if (record.kv.length > i) {
                        record.kv[i][0] = e.target.value
                      } else {
                        record.kv.push([e.target.value, ''])
                      }
                      this.cursor.set(record)
                      tree.commit()
                    }
                  })
                ]),
                h('td', [
                  focused
                    ? h('input.v', {
                      value: v,
                      onChange: e => {
                        let value = e.target.value

                        if (record.kv.length > i) {
                          record.kv[i][1] = value
                        } else {
                          record.kv.push(['', value])
                        }
                        this.cursor.set(record)
                        tree.commit()
                      }
                    })
                    : calcResults[i]
                ])
              ])
            )
          )
        ])
      ])
    )
  }
}

render(
  h(App),
  document.getElementById('app'),
)
