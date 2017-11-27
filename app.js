const React = require('react')
const render = require('react-dom').render
const cuid = require('cuid')
const h = require('react-hyperscript')
const styled = require('styled-components').default
const RGL = require('react-grid-layout')
const { getLayoutItem } = require('react-grid-layout/build/utils')
const { List, Map } = require('immutable')

const ReactGridLayout = RGL.WidthProvider(RGL)

const { db, KV } = require('./db')

class App extends React.Component {
  constructor () {
    super()

    this.state = {
      layout: [],
      draggable: false,
      records: Map()
    }
  }

  componentDidMount () {
    db.get('layout')
      .then(layout => {
        console.log('loaded layout', layout)
        this.setState({layout: layout.layout})
        this.layout_rev = layout._rev
      })
      .catch(e => console.log('error loading layout', e))

    this.changes = db.changes({include_docs: true, live: true})
    this.changes.on('change', ({doc}) => {
      if (doc._id.slice(0, 2) === 'r-') {
        console.log('record change', doc)
        var records

        if (doc._deleted) {
          records = this.state.records.delete(doc._id)
        } else {
          records = this.state.records.set(doc._id, doc)
        }

        this.setState({
          records: records
        })
      }
    })
  }

  componentWillUnmount () {
    this.changes.cancel()
  }

  render () {
    return (
      h('div', [
        h('.columns.is-mobile', [
          h('.column', 'data at "~"'),
          h('.column', [
            h('button.button.is-success', {
              onClick: () => this.setState({ draggable: !this.state.draggable })
            }, this.state.draggable ? 'done' : 'rearrange')
          ])
        ]),
        h(ReactGridLayout, {
          isDraggable: this.state.draggable,
          // items: 20,
          rowHeight: 24,
          cols: 14,
          onLayoutChange: (l) => this.saveLayout(l),
          // containerPadding: [12, 12],
          layout: this.state.layout
        }, this.state.records
          .toList()
          .push({
            /* a new record will be created when this blank is edited */ 
            _id: 'r-' + cuid.slug(),
            kv: []
          })
          .map(doc => {
            let layoutItem = getLayoutItem(this.state.layout, doc._id)
            console.log('item', doc._id, 'height', doc.kv.length + 1)

            return h('div', {
              key: doc._id,
              'data-grid': layoutItem
                ? Object.assign({h: doc.kv.length + 1}, layoutItem)
                : undefined
            }, [
              h(Document, doc)
            ])
          })
        )
      ])
    )
  }

  saveLayout (layout) {
    db.put({
      _id: 'layout',
      _rev: this.layout_rev,
      layout: layout
    })
      .then(r => {
        console.log('saved layout', r)
        this.layout_rev = r.rev
      })
      .catch(e => console.log('error saving layout', e))
  }
}

const doc = styled.div`
  background: white;
  height: 100%;
  font-family: monospace;
  overflow: hidden;

  table {
    width: 96%;
    margin: 0 2%;
  }

  td, th {
    height: 24px;
  }

  th {
    position: relative;
    text-align: right;

    &:after {
      position: absolute;
      right: 0;
      content: ": "
    }
  }

  input {
    width: 100%;
    height: 100%;
    border: none;
    padding: 0;
  }
`

class Document extends React.Component {
  constructor (props) {
    super(props)

    console.log('props', this.props)
    this.state = {
      kv: List(
        this.props.kv
          .map(([k, v]) => new KV({k, v}))
      )
    }
  }

  render () {
    return (
      h(doc, [
        h('table', {title: this.props._id}, [
          h('tbody', {}, this.state.kv
            .push(new KV())
            .map((kv, i) =>
              h('tr', {key: i}, [
                h('th', [
                  h('input', {
                    value: kv.get('k'),
                    onChange: e => this.set(i, 'k', e.target.value)
                  })
                ]),
                h('td', [
                  h('input', {
                    value: kv.get('v'),
                    onChange: e => this.set(i, 'v', e.target.value)
                  })
                ])
              ])
            )
          )
        ])
      ])
    )
  }

  set (index, what, value) {
    console.log('set', index, what, value)

    let kv = this.state.kv
      .update(index, new KV(), kv => kv.set(what, value))

    clearTimeout(this._saveTimeout)

    this.setState({
      kv: kv
    }, () => {
      // save doc
      this._saveTimeout = setTimeout(() => {
        db.put({
          _id: this.props._id,
          _rev: this.props._rev,
          kv: kv
            .map(kv => [kv.get('k'), kv.get('v')])
            .toArray()
        })
          .then(r => console.log('doc saved', r))
          .catch(e => console.log('error saving doc', e))
      }, 30000)
    })
  }
}

render(
  h(App),
  document.getElementById('app'),
)
