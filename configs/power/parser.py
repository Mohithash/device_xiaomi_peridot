import json

data = json.load(open('powerhint.json'))
nodes = data['Nodes']
actions = data['Actions']

node_names = [n['Name'] for n in nodes]
node_set = set(node_names)
node_map = {n['Name']: n for n in nodes}

# duplicate node names
dupes = set(n for n in node_names if node_names.count(n) > 1)
print('Duplicate node names:', dupes or 'none')

# actions referencing a node that doesn't exist
bad_refs = [(i, a) for i, a in enumerate(actions)
            if a.get('Type') != 'EndHint' and a.get('Node') not in node_set]
print('Bad node refs:', bad_refs or 'none')

# nodes missing a Path/Paths
bad_nodes = [n['Name'] for n in nodes if 'Path' not in n and 'Paths' not in n]
print('Nodes missing Path:', bad_nodes or 'none')

# DefaultIndex out of range
for n in nodes:
    if 'DefaultIndex' in n and not (0 <= n['DefaultIndex'] < len(n['Values'])):
        print('Bad DefaultIndex:', n['Name'])

# Action value not in the node's allowed Values list — THIS is the one that caught your bug
for i, a in enumerate(actions):
    if a.get('Type') == 'EndHint':
        continue
    node = node_map.get(a.get('Node'))
    if node and a.get('Value') not in node['Values']:
        print(f'Action {i} bad value: {a["Node"]} = {a["Value"]!r}, allowed: {node["Values"]}')
