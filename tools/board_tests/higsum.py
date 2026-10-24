import json,sys
d=json.load(open(sys.argv[1]))
for k,v in d.items():
    print(f"== {k}: texts {v['texts']} min {v['minText']} | small {sum(x['n'] for x in v['small'])} | thin {len(v['thin'])} | contrast {sum(x['n'] for x in v['contrast'])} | targets<def {sum(x['n'] for x in v['targets'])} | <min {sum(x['n'] for x in v['targetsMin'])} | rm {v['rm']} | docW {v['docW']}/{v['vw']}")
