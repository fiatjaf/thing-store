const React = require('react')
const render = require('react-dom').render
const cuid = require('cuid')
const h = require('react-hyperscript')
const styled = require('styled-components').default
const hashbow = require('hashbow')
const RGL = require('react-grid-layout')
const { getLayoutItem } = require('react-grid-layout/build/utils')

const ReactGridLayout = RGL.WidthProvider(RGL)

const { tree } = require('./state')

class App extends React.Component {
  constructor () {
    super()

    this.recordsCursor = tree.select('records')
    this.draggableCursor = tree.select('draggable')
  }

  componentDidMount () {
    this.recordsCursor.on('update', () => {
      this.forceUpdate()
    })
    this.draggableCursor.on('update', () => { this.forceUpdate() })
  }

  componentWillUnmount () {
    this.recordsCursor.release()
    this.draggableCursor.release()
  }

  render () {
    let {layout, draggable, records} = tree.project({
      layout: ['layout', 'layout'],
      draggable: ['draggable'],
      records: ['records']
    })

    return (
      h('div', [
        h('.columns.is-mobile', [
          h('.column', 'data at "~"'),
          h('.column', [
            h('button.button.is-success', {
              onClick: () => tree.set('draggable', !draggable)
            }, draggable ? 'done' : 'rearrange')
          ])
        ]),
        h(ReactGridLayout, {
          isDraggable: draggable,
          items: 40,
          rowHeight: 30,
          cols: 12,
          onLayoutChange: l => tree.set(['layout', 'layout'], l),
          containerPadding: [12, 12],
          margin: [0, 0],
          autoSize: false,
          layout: layout
        }, Object.keys(records)
          .map(_id => records[_id])
          .concat({
            /* a new record will be created when this blank is edited */ 
            _id: 'r-' + cuid.slug(),
            kv: []
          })
          .map(record => {
            let layoutItem = getLayoutItem(layout, record._id)
            console.log('item', record._id, 'height', record.kv.length + 1)

            return h('div', {
              key: record._id,
              'data-grid': layoutItem
                ? Object.assign(layoutItem, {h: record.kv.length + 1})
                : undefined
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
  background-color: 2px solid ${props => hashbow(props.id)};

  table {
    background-color: white;
    width: 100%;
    margin: 0;
    border-collapse: collapse;
    border-spacing: 0;
  }

  td, th {
    height: 30px;
    border: 1px solid #dbdbdb;
  }

  th {
    width: 39%;
    max-width: 100px;
    position: relative;
    background-color: #f6f1f6;

    &:after {
      content: ": ";
      position: absolute;
      right: 0;
    }

    input {
      text-align: right;
    }
  }

  input {
    width: 100%;
    height: 100%;
    border: none;
    padding-right: 4px;
    font-family: monospace;
    background-color: inherir;

    &:focus {
      background-color: #def6ff;
    }
  }
`

class Document extends React.Component {
  constructor (props) {
    super(props)

    this.cursor = tree.select(['records', this.props._id])
  }

  componentDidMount () {
    this.cursor.on('update', () => { this.forceUpdate() })
  }

  componentWillUnmount () {
    this.cursor.tree && this.cursor.release()
  }

  shouldComponentUpdate (nextProps) {
    return this.props._id !== nextProps._id
  }

  render () {
    let record = this.cursor.get() || {_id: this.props._id, kv: []}

    return (
      h(docDiv, {id: record._id}, [
        h('table', {title: record._id}, [
          h('tbody', {}, record
            .kv
            .concat([['', '']])
            .map(([k, v], i) => console.log('kv', k, v, i) ||
              h('tr', {key: i, id: k}, [
                h('th', [
                  h('input', {
                    value: k,
                    onChange: e => {
                      if (record.kv.length > i) {
                        record.kv[i][0] = e.target.value
                      } else {
                        record.kv.push([e.target.value, ''])
                      }
                      this.cursor.apply(() => record)
                      tree.commit()
                    }
                  })
                ]),
                h('td', [
                  h('input', {
                    value: v,
                    onChange: e => {
                      if (record.kv.length > i) {
                        record.kv[i][1] = e.target.value
                      } else {
                        record.kv.push(['', e.target.value])
                      }
                      this.cursor.apply(() => record)
                      tree.commit()
                    }
                  })
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
