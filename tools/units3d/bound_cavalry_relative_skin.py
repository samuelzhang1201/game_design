"""Necessary native relative-skin domains; excluding a saved point closes no shape.

Proof identity: Sc = Sp C + Dg Bc + Dc - Dp C, C = inverse(Bp) Lc Bc.
Native multiplication is never reassociated. All matrices below are augmented4x4;
error matrices have a zero bottom row, unlike affine pose/bind matrices.
"""
import ast
from fractions import Fraction as Q
from functools import lru_cache
import hashlib
import json
import math
from pathlib import Path
from types import SimpleNamespace

ROOT = Path(__file__).resolve().parents[2]
HELPER_SHA = 'a8678036793b5588b99e9a43fa825283bd41d80b75bf20a28cfbb1d51c41eec9'
SCALAR_SHA = '37f34e84334c12ed9194539d4e16505e461927ad17fd84553931f2e60ff9dc4f'
EXCLUDED = 'THIS_WITNESS_EXCLUDED_BY_NATIVE_RELATION'
NOT_EXCLUDED = 'NOT_EXCLUDED_BY_THIS_BOUND'


def require(value, message):
    if not value: raise ValueError(message)


def exact(value):
    require(type(value) in (int,float,Q) and (type(value) is not float or math.isfinite(value)), 'Invalid exact scalar')
    return Q(value)


def packed(value):
    if isinstance(value,Q): return [value.numerator,value.denominator]
    if isinstance(value,(tuple,list)): return [packed(v) for v in value]
    if isinstance(value,dict): return {k:packed(v) for k,v in value.items()}
    return value


def digest(value):
    return hashlib.sha256(json.dumps(packed(value),sort_keys=True,separators=(',',':'),allow_nan=False).encode()).hexdigest()


def matrix(value):
    require(len(value)==4 and all(len(row)==4 for row in value),'Expected augmented4x4 matrix')
    return tuple(tuple(map(exact,row)) for row in value)


def affine(value):
    result=matrix(value)
    require(result[3]==(0,0,0,1),'Nonaffine bottom row')
    return result


def matmul(a,b):
    a,b=matrix(a),matrix(b)
    return tuple(tuple(sum(a[i][k]*b[k][j] for k in range(4)) for j in range(4)) for i in range(4))


def matadd(a,b):
    return tuple(tuple(x+y for x,y in zip(ar,br)) for ar,br in zip(matrix(a),matrix(b)))


def negate(a): return tuple(tuple(-v for v in row) for row in matrix(a))


def affine_inverse(value):
    value=affine(value)
    rows=[list(row)+[Q(i==j) for j in range(4)] for i,row in enumerate(value)]
    for column in range(4):
        pivot=next((i for i in range(column,4) if rows[i][column]),None)
        require(pivot is not None,'Singular true Skin bind')
        rows[column],rows[pivot]=rows[pivot],rows[column]
        divisor=rows[column][column];rows[column]=[v/divisor for v in rows[column]]
        for i in range(4):
            if i!=column:
                factor=rows[i][column];rows[i]=[a-factor*b for a,b in zip(rows[i],rows[column])]
    result=tuple(tuple(row[4:]) for row in rows)
    require(matmul(value,result)==matmul(result,value)==tuple(tuple(Q(i==j) for j in range(4)) for i in range(4)), 'Exact bind inverse failed')
    return affine(result)


def transport_residual(dp,dg,dc,bc,c):
    return matadd(matadd(matmul(dg,bc),dc),negate(matmul(dp,c)))


def point_box(value): return [[(v,v) for v in row] for row in matrix(value)]


def interval_box(value, affine_bottom=False):
    require(len(value)==4 and all(len(row)==4 for row in value),'Expected full4x4 interval matrix')
    result=[]
    for row in value:
        converted=[]
        for pair in row:
            require(len(pair)==2,'Missing interval endpoint')
            lo,hi=map(exact,pair);require(lo<=hi,'Reversed interval');converted.append((lo,hi))
        result.append(converted)
    if affine_bottom: require(result[3]==[(Q(0),Q(0))]*3+[(Q(1),Q(1))],'Nonaffine interval bottom row')
    return result


def interval_product(a,b):
    values=[x*y for x in a for y in b]
    return min(values),max(values)


def boxmul(a,b):
    a,b=interval_box(a),interval_box(b)
    output=[]
    for i in range(4):
        row=[]
        for j in range(4):
            terms=[interval_product(a[i][k],b[k][j]) for k in range(4)]
            row.append((sum(v[0] for v in terms),sum(v[1] for v in terms)))
        output.append(row)
    return output


def boxadd(a,b):
    a,b=interval_box(a),interval_box(b)
    return [[(x[0]+y[0],x[1]+y[1]) for x,y in zip(ar,br)] for ar,br in zip(a,b)]


def boxneg(a): return [[(-hi,-lo) for lo,hi in row] for row in interval_box(a)]


def source_bytes(path,expected):
    value=Path(path).read_bytes()
    require(hashlib.sha256(value).hexdigest()==expected,'Accepted source changed: '+str(path))
    return value


def pure_functions(source,names,namespace):
    tree=ast.parse(source)
    nodes=[node for node in tree.body if isinstance(node,ast.FunctionDef) and node.name in names]
    require({n.name for n in nodes}==set(names),'Missing accepted pure primitive')
    exec(compile(ast.Module(body=nodes,type_ignores=[]),'<hash-pinned pure primitives>','exec'),namespace)
    return namespace


@lru_cache(maxsize=1)
def rounding_authority():
    scalar=pure_functions(source_bytes(ROOT/'tools/units3d/royal_native_arithmetic/prove.py',SCALAR_SHA),
        ['floor_log2','up','minnormal','rnd'],{'F':Q,'require':require})
    authority=SimpleNamespace(**{key:scalar[key] for key in ('rnd','minnormal')})
    helper=pure_functions(source_bytes(ROOT/'tools/units3d/cavalry_march_phase.py',HELPER_SHA),
        ['roundoff_sum'],{'scalar':authority})
    authority.roundoff_sum=helper['roundoff_sum']
    return authority


def native_product_error(a,b,authority):
    """Accepted point-error budget, applied to each actual affine output graph.

    Input flushing never increases operand magnitude. A flushed product differs
    by at most tiny*(|a|+|b|); six tiny allowances cover the three adds' inputs.
    This is the pinned _skin_vertex_residual point_error formula before weights.
    roundoff_sum covers directed rounding/outputFTZ and optional contraction;
    an origin summand receives its existing conservative extra rounding budget.
    """
    a,b=interval_box(a,True),interval_box(b,True);tiny=authority.minnormal(24)
    magnitude=lambda pair:max(map(abs,pair))
    absolute=[[Q(0)]*4 for _ in range(4)];cells=[]
    for i in range(3):
        left=[magnitude(a[i][k]) for k in range(3)]
        for j in range(4):
            right=[magnitude(b[k][j]) for k in range(3)]
            require(all(v<Q(2)**100 for v in left+right),'Consumed affine operand outside accepted finite bound')
            terms=[x*y for x,y in zip(left,right)]
            if j==3:terms.append(magnitude(a[i][3]))
            rounding=authority.roundoff_sum(terms)
            flushing=tiny*(sum(left)+sum(right)+6)
            absolute[i][j]=rounding+flushing
            cells.append({'axis':i,'column':j,'left_magnitudes':left,'right_magnitudes':right,
                          'terms':terms,'rounding':rounding,'input_flush':flushing})
    return {'absolute':absolute,'source_nodes':{'multiply':36,'add':27},'cells':cells}


def symmetric(absolute): return [[(-exact(v),exact(v)) for v in row] for row in matrix(absolute)]


def native_product_box(a,b,authority):
    return boxadd(boxmul(a,b),symmetric(native_product_error(a,b,authority)['absolute']))


def compile_constraint(parent_global,child_local,bp,bc,authority):
    bp,bc=affine(bp),affine(bc);parent_global=interval_box(parent_global,True);child_local=interval_box(child_local,True)
    inverse=affine_inverse(bp)
    c=boxmul(boxmul(point_box(inverse),child_local),point_box(bc))
    graphs={'Dp':native_product_error(parent_global,point_box(bp),authority),
            'Dg':native_product_error(parent_global,child_local,authority)}
    gc=boxadd(boxmul(parent_global,child_local),symmetric(graphs['Dg']['absolute']))
    graphs['Dc']=native_product_error(gc,point_box(bc),authority)
    dp,dg,dc=[symmetric(graphs[key]['absolute']) for key in ('Dp','Dg','Dc')]
    residual=boxadd(boxadd(boxmul(dg,point_box(bc)),dc),boxneg(boxmul(dp,c)))
    return {'bind_inverse':inverse,'C':c,'R':residual,'Dp':dp,'Dg':dg,'Dc':dc,'Gc':gc,'graphs':graphs}


def replay_constraint(parent_global,child_local,bp,bc,record,authority):
    """Replay every proof object without calling the constraint compiler."""
    record={**record,**{key:interval_box(record[key]) for key in ('C','R','Dp','Dg','Dc','Gc')}}
    bp,bc=affine(bp),affine(bc);inverse=affine(record['bind_inverse'])
    identity=tuple(tuple(Q(i==j) for j in range(4)) for i in range(4))
    require(matmul(bp,inverse)==matmul(inverse,bp)==identity,'Replayed bind inverse differs')
    expected_c=boxmul(boxmul(point_box(inverse),child_local),point_box(bc))
    require(interval_box(record['C'],True)==expected_c,'Relative local domain/outward endpoint differs')
    for key,left,right in [('Dp',parent_global,point_box(bp)),('Dg',parent_global,child_local),('Dc',record['Gc'],point_box(bc))]:
        graph=native_product_error(left,right,authority)
        require(record['graphs'][key]==graph and interval_box(record[key])==symmetric(graph['absolute']),'Missing/altered analytic residual graph: '+key)
        require(record[key][3]==[(Q(0),Q(0))]*4,'Residual bottom row is not zero')
    expected_gc=boxadd(boxmul(parent_global,child_local),record['Dg'])
    require(interval_box(record['Gc'],True)==expected_gc,'Rounded native child-global domain differs')
    expected_r=boxadd(boxadd(boxmul(record['Dg'],point_box(bc)),record['Dc']),boxneg(boxmul(record['Dp'],record['C'])))
    require(interval_box(record['R'])==expected_r and record['R'][3]==[(Q(0),Q(0))]*4,'Missing/signed/outward transport residual differs')
    return True


def audit_point(wp,wc,relation):
    if relation is None:return {'status':'UNRESOLVED'}
    wp,wc=affine(wp),affine(wc)
    bounds=boxadd(boxmul(point_box(wp),interval_box(relation['C'],True)),relation['R'])
    for i in range(3):
        for j in range(4):
            lo,hi=bounds[i][j];value=wc[i][j]
            if value<lo or value>hi:
                return {'status':EXCLUDED,'witness_sha256':digest([wp,wc]),'separation':{'axis':i,'column':j,'value':value,'lower':lo,'upper':hi,'side':'below' if value<lo else 'above'}}
    return {'status':NOT_EXCLUDED,'witness_sha256':digest([wp,wc])}


def replay_separation(wp,wc,relation,record):
    wp,wc=affine(wp),affine(wc)
    require(record.get('witness_sha256')==digest([wp,wc]),'Saved witness point changed')
    bounds=boxadd(boxmul(point_box(wp),relation['C']),relation['R'])
    if record['status']==NOT_EXCLUDED:
        require(all(lo<=wc[i][j]<=hi for i,row in enumerate(bounds) for j,(lo,hi) in enumerate(row)),'Unexcluded witness leaves necessary domain')
    else:
        require(record['status']==EXCLUDED,'Unknown witness disposition')
        proof=record['separation'];i,j=proof['axis'],proof['column']
        require(type(i) is int and type(j) is int and 0<=i<3 and 0<=j<4,'Invalid separated component')
        lo,hi=bounds[i][j];value=wc[i][j]
        require((proof['value'],proof['lower'],proof['upper'])==(value,lo,hi),'Strict separation endpoint changed')
        require(proof['side']=='below' and value<lo or proof['side']=='above' and value>hi,'Separation is not strict')
    return True

# Only this step's compile/verify paths consume these pure, hash-pinned helpers.
NATIVE_SHA = '2eeff65cc1ff6e4dc29882917ff776c98c0d8c119776aa9163a790ef58030adc'
FORBIDDEN = {'surface_span_box','surface_points','sampled_points','build','main','load_inputs',
             'acquire','run','system_math','math_runtime_identity','load_capture','audit'}


def source_subset(source,roots):
    tree=ast.parse(source);definitions={}
    for node in tree.body:
        if isinstance(node,(ast.FunctionDef,ast.ClassDef)):definitions[node.name]=node
        elif isinstance(node,ast.Assign):
            for target in node.targets:
                if isinstance(target,ast.Name):definitions[target.id]=node
    needed=set();pending=set(roots)-{'__file__'}
    while pending:
        name=pending.pop()
        require(name not in FORBIDDEN,'Forbidden producer/capture helper dependency: '+name)
        require(name in definitions,'Missing pure source dependency: '+name)
        if name in needed:continue
        needed.add(name)
        pending.update(n.id for n in ast.walk(definitions[name]) if isinstance(n,ast.Name)
                       and isinstance(n.ctx,ast.Load) and n.id in definitions and n.id not in needed)
    selected={id(definitions[name]) for name in needed}
    nodes=[node for node in tree.body if id(node) in selected]
    attributes={alias:{n.attr for node in nodes for n in ast.walk(node)
                       if isinstance(n,ast.Attribute) and isinstance(n.value,ast.Name) and n.value.id==alias}
                for alias in ('native','scalar')}
    return tree,nodes,attributes


def execute_subset(path,tree,nodes,external):
    import sys
    import types
    module=types.ModuleType('_relative_pure_'+Path(path).stem)
    module.__file__=str(path);sys.modules[module.__name__]=module
    namespace=module.__dict__;namespace.update(external)
    allowed={'__future__','argparse','ast','bisect','collections','csv','ctypes','dataclasses',
             'fractions','functools','hashlib','json','math','numpy','os','pathlib','platform',
             're','shutil','struct','subprocess','sys','tempfile','time','typing'}
    for node in tree.body:
        if isinstance(node,ast.Import):
            if all(alias.name.split('.')[0] in allowed for alias in node.names):
                exec(compile(ast.Module(body=[node],type_ignores=[]),str(path),'exec'),namespace)
        elif isinstance(node,ast.ImportFrom) and node.module.split('.')[0] in allowed:
            exec(compile(ast.Module(body=[node],type_ignores=[]),str(path),'exec'),namespace)
    exec(compile(ast.Module(body=nodes,type_ignores=[]),str(path),'exec'),namespace)
    return module


def ftz_closed_box(value,bits=24):
    import numpy as np
    tiny=float(Q(2)**(-126 if bits==24 else -1022))
    lo,hi=value.lo,value.hi
    if np.any((lo>0)&(lo<tiny)|(hi<0)&(hi>-tiny)):
        raise ValueError('Missing existing interval primitive authority: FTZ would add an unenclosed zero '+json.dumps({'precision':bits,'lower':np.asarray(lo).tolist(),'upper':np.asarray(hi).tolist()}))


def guard_local_primitives(native,helper):
    original=native.Float32Box
    class GuardedBox(original):
        @classmethod
        def outward(cls,lo,hi):
            value=original.outward.__func__(cls,lo,hi);ftz_closed_box(value);return value
    def guarded(method):
        def call(self,*args):
            ftz_closed_box(self)
            for value in args:
                if hasattr(value,'lo'):ftz_closed_box(value)
            return method(self,*args)
        return call
    for name in ('__add__','__mul__','__truediv__','sqrt'):
        setattr(GuardedBox,name,guarded(getattr(original,name)))
    native.Float32Box=GuardedBox
    for name in ('interval_product','interval_quotient'):
        original_function=getattr(helper,name)
        def checked(a,b,bits,function=original_function):
            tiny=Q(2)**(-126 if bits==24 else -1022)
            require(all(not (0<x[0]<tiny or -tiny<x[1]<0) for x in (a,b)),
                    'Missing existing scalar primitive authority: FTZ would add an unenclosed zero')
            return function(a,b,bits)
        setattr(helper,name,checked)


@lru_cache(maxsize=1)
def range_authority():
    helper_path=ROOT/'tools/units3d/cavalry_march_phase.py'
    native_path=ROOT/'tools/units3d/check_cavalry_march_capture.py'
    scalar_path=ROOT/'tools/units3d/royal_native_arithmetic/prove.py'
    tree,nodes,attributes=source_subset(source_bytes(helper_path,HELPER_SHA),
        {'track_span_box','mixer_span_box','basis_span_box','Budget','ScalarAuthority','roundoff_sum'})
    ntree,nnodes,_=source_subset(source_bytes(native_path,NATIVE_SHA),attributes['native']|{'matrix'})
    stree,snodes,_=source_subset(source_bytes(scalar_path,SCALAR_SHA),attributes['scalar'])
    native=execute_subset(native_path,ntree,nnodes,{})
    scalar=execute_subset(scalar_path,stree,snodes,{})
    helper=execute_subset(helper_path,tree,nodes,{'native':native,'scalar':scalar})
    guard_local_primitives(native,helper)
    return helper


def resolved_pair(native,group):
    require(len(group)==2 and len(set(group))==2,'A relative relation needs exactly two binds')
    bones,skin=native['bones'],native['skin']
    require(all(type(i) is int and 0<=i<len(skin) for i in group),'Unknown native bind')
    for index in group:
        binding=skin[index];bone=binding['resolved_bone']
        require(0<=bone<len(bones) and binding['name']==bones[bone]['name'],'True Skin bind-to-bone mapping differs')
    a,b=group;ia,ib=skin[a]['resolved_bone'],skin[b]['resolved_bone']
    if bones[ib]['parent']==ia:return a,b,ia,ib
    require(bones[ia]['parent']==ib,'Actual two-bind group is not immediate parent/child')
    return b,a,ib,ia


def native_bind(binding):
    values=binding['pose'];require(len(values)==12,'Malformed captured true affine bind')
    return affine([values[i:i+4] for i in (0,4,8)]+[[0,0,0,1]])


def local_context(native,seconds,ranges,budget):
    lo,hi=seconds;require(0<=lo<=hi<=native['length'],'Unadmitted native phase')
    f=ranges.native.Float32Box
    def forbidden_libm(*args):raise ValueError('Unaccepted live libm replay in relative-skin proof')
    functions={name:forbidden_libm for name in ('sin','sinf','acosf')}
    tracks={}
    for track in native['tracks']:
        key=(track['path'].split(':')[-1],track['type'])
        require(key not in tracks and track['type'] in (1,2) and track['enabled'] is True and track['compressed'] is False and track['loop_wrap'] is True and track['interpolation'] in (0,1),'Unsupported native track/search/scale branch')
        tracks[key]=ranges.track_span_box(track,lo,hi,native['length'],functions,budget)
    locals_=[];certificates=[]
    for bone in native['bones']:
        position,rotation=f(bone['default_position']),f(bone['default_rotation'])
        if (bone['name'],1) in tracks:
            rest=f(ranges.native.matrix(bone['rest'])[:3,3]);position=rest+(tracks[bone['name'],1]-rest)
        if (bone['name'],2) in tracks:rotation=ranges.mixer_span_box(bone['rest_rotation'],tracks[bone['name'],2])
        local=ranges.basis_span_box(position,rotation,bone['default_scale'])
        locals_.append([[(exact(float(local.lo[i,j])),exact(float(local.hi[i,j]))) for j in range(4)] for i in range(3)]+[[(Q(0),Q(0))]*3+[(Q(1),Q(1))]])
        if isinstance(rotation,ranges.QuaternionSpan):
            branches=[{**b.certificate,'basis_rounded_norm_squared':ranges.rounded_norm(b,'basis')[0]} for b in rotation.branches]
            budget.norm_records[lo,hi,bone['name']]=branches
            certificates.append({'seconds':seconds,'bone':bone['name'],'branches':ranges.json_value(branches)})
    return locals_,certificates


def global_context(native,locals_,authority):
    require(len(locals_)==len(native['bones']),'Local pose denominator differs')
    globals_=[]
    for index,(bone,local) in enumerate(zip(native['bones'],locals_)):
        parent=bone['parent'];require(type(parent) is int and -1<=parent<index,'Native FK hierarchy differs')
        globals_.append(local if parent<0 else native_product_box(globals_[parent],local,authority))
    return globals_



def context_call(context_id,seconds,stage,function,*args):
    try:return function(*args)
    except ValueError as error:
        detail=getattr(error,'detail',None)
        if detail is not None:detail=range_authority().json_value(detail)
        raise ValueError(json.dumps({'context_sha256':context_id,'seconds':seconds,'stage':stage,
                                    'reason':str(error),'source_detail':detail},sort_keys=True)) from error


def compile_domains(packet,ranges,scalar,authority):
    require(0<len(packet['contexts'])<=47,'Original full context bound exceeded')
    native=packet['native'];pairs=[resolved_pair(native,group) for group in packet['pairs']]
    binds={i:native_bind(native['skin'][i]) for group in packet['pairs'] for i in group}
    for bind in binds.values():affine_inverse(bind)
    budget=ranges.Budget(arithmetic=scalar);result={}
    for context_id,context in sorted(packet['contexts'].items()):
        require(digest(context)==context_id,'Changed original context/time/source identity')
        locals_,certificates=context_call(context_id,context['seconds'],'track_mixer_Basis',local_context,native,context['seconds'],ranges,budget)
        globals_=context_call(context_id,context['seconds'],'native_FK',global_context,native,locals_,authority);relations={}
        for p,c,pbone,cbone in pairs:
            relations[str(p)+':'+str(c)]={'parent_bind':p,'child_bind':c,'parent_bone':pbone,'child_bone':cbone,
                'proof':context_call(context_id,context['seconds'],'relative_pair:'+str(p)+':'+str(c),compile_constraint,globals_[pbone],locals_[cbone],binds[p],binds[c],authority)}
        result[context_id]={'seconds':context['seconds'],'source_sha256':context['source_sha256'],
            'locals':locals_,'globals':globals_,'local_certificates':certificates,'relations':relations}
    check_range_budget(native,budget,scalar,ranges)
    return result


def witness_pair(packet,job,p,c):
    context=packet['contexts'][job['shared_transform_sha256']]
    low,high=context['matrix_interval'];variables=job['variables'];assignment=job['proof']['assignment']
    require(job['unused_matrix_entries']=='exact_interval_midpoint','Changed unused native matrix-entry rule')
    require(variables==sorted(set(map(tuple,variables))) or variables==[list(v) for v in sorted(set(map(tuple,variables)))],'Missing/duplicate/reordered matrix variables')
    require(len(assignment)==3 and all(len(row)==len(variables) for row in assignment),'Saved witness assignment denominator differs')
    def rational(pair):
        require(type(pair) is list and len(pair)==2 and all(type(v) is int for v in pair) and pair[1]>0 and math.gcd(*pair)==1,'Missing/noncanonical witness denominator')
        return Q(*pair)
    matrices={joint:[[(exact(low[joint][axis][k])+exact(high[joint][axis][k]))/2 for k in range(4)] for axis in range(3)]+[[Q(0),Q(0),Q(0),Q(1)]] for joint in (p,c)}
    for axis,row in enumerate(assignment):
        for (joint,column),encoded in zip(variables,row):
            value=rational(encoded)
            require(joint in matrices and type(column) is int and 0<=column<4 and exact(low[joint][axis][column])<=value<=exact(high[joint][axis][column]),'Witness point left its exact original rectangle')
            matrices[joint][axis][column]=value
    return affine(matrices[p]),affine(matrices[c])


def audit_jobs(packet,domains):
    output={}
    for job_id,job in sorted(packet['jobs'].items()):
        status=job['proof']['status'];group=sorted({joint for joint,column in job['variables']})
        record={'old_status':status,'source_sha256':job['certificate_sha256'],'context_sha256':job['shared_transform_sha256'],'bind_group':group}
        if len(group)==2:
            p,c,_,_=resolved_pair(packet['native'],group);record['relation']=str(p)+':'+str(c)
        if len(group)==1:record['audit']={'status':'NOT_APPLICABLE_SINGLE_BIND'}
        elif status=='REFERENCE_BOX_NONDEGENERATE':record['audit']={'status':'ORIGINAL_NONDEGENERATE_RESULT_PRESERVED'}
        else:
            require(status=='REFERENCE_BOX_DEGENERATE','Unexpected predecessor matrix result')
            p,c,_,_=resolved_pair(packet['native'],group);key=str(p)+':'+str(c)
            relation=domains.get(job['shared_transform_sha256'],{}).get('relations',{}).get(key)
            if relation is None:record['audit']={'status':'UNRESOLVED'}
            else:
                wp,wc=witness_pair(packet,job,p,c);record['relation']=key
                record['audit']=audit_point(wp,wc,relation['proof'])
        output[job_id]=record
    return output


def replay_domains_and_audits(packet,domains,audits,ranges,scalar,authority):
    require(set(domains)==set(packet['contexts']) and set(audits)==set(packet['jobs']),'Missing context/group/job denominator')
    native=packet['native'];pairs=[resolved_pair(native,group) for group in packet['pairs']]
    expected_groups={str(p)+':'+str(c) for p,c,_,_ in pairs};budget=ranges.Budget(arithmetic=scalar)
    for context_id,source in sorted(packet['contexts'].items()):
        require(digest(source)==context_id,'Stale replay context/time/source')
        record=domains[context_id]
        require(record['seconds']==source['seconds'] and record['source_sha256']==source['source_sha256'] and set(record['relations'])==expected_groups,'Stale or missing branch/group relation')
        locals_,certificates=context_call(context_id,source['seconds'],'replay_track_mixer_Basis',local_context,native,source['seconds'],ranges,budget)
        require(record['locals']==locals_ and record['local_certificates']==certificates,'Local/Basis/key/sign/normalization branch replay differs')
        globals_=context_call(context_id,source['seconds'],'replay_native_FK',global_context,native,locals_,authority);require(record['globals']==globals_,'Native parent FK magnitude replay differs')
        for p,c,pbone,cbone in pairs:
            relation=record['relations'][str(p)+':'+str(c)]
            require([relation[k] for k in ('parent_bind','child_bind','parent_bone','child_bone')]==[p,c,pbone,cbone],'Actual bind direction changed')
            replay_constraint(globals_[pbone],locals_[cbone],native_bind(native['skin'][p]),native_bind(native['skin'][c]),relation['proof'],authority)
    check_range_budget(native,budget,scalar,ranges)
    for job_id,job in packet['jobs'].items():
        record=audits[job_id];group=sorted({joint for joint,column in job['variables']});status=job['proof']['status']
        require(record['old_status']==status and record['source_sha256']==job['certificate_sha256'] and record['context_sha256']==job['shared_transform_sha256'] and record['bind_group']==group,'Original witness/source/context/status changed')
        if len(group)==1:require(record['audit']=={'status':'NOT_APPLICABLE_SINGLE_BIND'},'Dropped single-bind disposition')
        elif status=='REFERENCE_BOX_NONDEGENERATE':
            p,c,_,_=resolved_pair(native,group)
            require(record['relation']==str(p)+':'+str(c) and record['audit']=={'status':'ORIGINAL_NONDEGENERATE_RESULT_PRESERVED'},'Relabelled or unbound predecessor nondegenerate result')
        else:
            p,c,_,_=resolved_pair(native,group);key=str(p)+':'+str(c)
            require(record['relation']==key,'Saved point relation changed')
            wp,wc=witness_pair(packet,job,p,c)
            replay_separation(wp,wc,domains[job['shared_transform_sha256']]['relations'][key]['proof'],record['audit'])
    return True


def unpack_math(value):
    if isinstance(value,list):
        if len(value)==2 and all(type(v) is int for v in value):
            require(value[1]>0 and math.gcd(*value)==1,'Invalid/noncanonical proof denominator')
            return Q(*value)
        return [unpack_math(v) for v in value]
    if isinstance(value,dict):return {k:unpack_math(v) for k,v in value.items()}
    require(type(value) in (int,str),'Unexpected scalar in exact proof')
    return value


def decode_domains(value):
    output={}
    for context_id,record in value.items():
        decoded={**record,'locals':[interval_box(v) for v in unpack_math(record['locals'])],
                 'globals':[interval_box(v) for v in unpack_math(record['globals'])],'relations':{}}
        for pair,relation in record['relations'].items():
            proof=unpack_math(relation['proof']);proof['bind_inverse']=affine(proof['bind_inverse'])
            for field in ('C','R','Dp','Dg','Dc','Gc'):proof[field]=interval_box(proof[field])
            decoded['relations'][pair]={**relation,'proof':proof}
        output[context_id]=decoded
    return output


def decode_audits(value):
    output={}
    for key,record in value.items():
        audit={**record['audit']}
        if 'separation' in audit:
            audit['separation']={k:unpack_math(v) if k in ('value','lower','upper') else v for k,v in audit['separation'].items()}
        output[key]={**record,'audit':audit}
    return output


def signature(path):
    stat=Path(path).stat();return stat.st_dev,stat.st_ino,stat.st_size,stat.st_mtime_ns


def read_checked(path,expected,watched,size=None,parse=True):
    path=Path(path).resolve();before=signature(path);raw=path.read_bytes()
    require(hashlib.sha256(raw).hexdigest()==expected and (size is None or len(raw)==size),'Changed/missing frozen input: '+str(path))
    require(signature(path)==before,'Input changed during cold read: '+str(path));watched.append((path,before))
    if not parse:return None
    def nonfinite(value):raise ValueError('Nonfinite frozen JSON value: '+value)
    return json.loads(raw,parse_constant=nonfinite)


def unchanged(watched):
    require(all(signature(path)==before for path,before in watched),'Input changed during proof/replay')


def target_audits(previous,audits):
    def statuses(ids):return None if ids is None else [audits[key]['audit']['status'] for key in ids]
    result={}
    for kind,field in [('area','area_dispositions'),('birth','birth_dispositions')]:
        result[kind]=[{'predecessor':row,'parent':statuses(row['parent_jobs']),
            'children':None if row['child_jobs'] is None else [statuses(ids) for ids in row['child_jobs']],
            'meaning':'Saved points only; no effective geometry closure'} for row in previous[field]]
    return result


PINS = {
    'authority':'90ee1dd486064c0218c9396d540775885822ccac24eafa2bd660153a005266e8',
    'metadata_receipt':'4d18bc43ebe777c93d75919d03b7d8eaa3dc644855e9a7ddd02a87edc8bf356d',
    'report':'e7137a7ccfbd1559b8f2736565e4f7eafff6acff2f8afc5e85b517ad0f32c04c',
    'receipt':'9bb49daf0da931fdb167690328da88c301b8e1097b3e58920e769078418572ed',
    'remaining':'a6dcf6bd48b442ee355aaa181aa676d2db8d7b9893fb6add393a8e8d5eefbbbd',
    'sidecar':'24c4eaada0e80f2282a91af10c5ec485503e4387c4a67c369457008edffc7c9c',
    'ledger':'d88e189f039efa42bf7172b8e6d8e3a156f007e2bc86593615b78b6c93fc8782',
    'predecessor_receipt':'6b05c070350799d7fb67932458c19d1a4a8f24bc88a898a244f852fd752f4371',
    'predecessor_plan':'1a40ed2d292db003e1b6c2bed5aaaa9cb441ae6776dd929c258b7bd48a042115',
    'predecessor_replay':'5a3ab2269bed68a35c3b750f4defc56fbb2d413ec863b8afddb81cbb57935e8d',
    'native_manifest':'3e4a9fe377e1b4d031b7653fd7027bbc195e2c2f46f9c264f1f20cea803beb2c',
    'native_review':'313dd42b38820705e7ff369e89ff1799bbc01b6a47a6b9e7894f3682bd93ed0b',
    'arithmetic_capture':'b3e222429c5b311fea2d87cb9c77354efead9418bdd28b413ef98a86d02440a1',
    'arithmetic_receipt':'d03096ad4725b417a6ee858c1578468bc588a5bd2a9dabcdd2dc2153869a9301'}
PAIRS = [[4,5],[8,9],[43,44],[48,49]]


def load_inputs(args):
    watched=[];inputs={}
    for name,pin in PINS.items():
        inputs[name]=read_checked(getattr(args,name),pin,watched,
            size=498049055 if name=='report' else 106526330 if name=='authority' else None,parse=name!='report')
    authority=inputs['authority'];metadata=inputs['metadata_receipt'];previous=inputs['sidecar'];ledger=inputs['ledger']['accepted_input_bindings']
    require(metadata['status']=='COMPLETE_METADATA_CONTEXT_AUTHORITY_PASS_NO_ANALYTIC_ACCEPTANCE' and metadata['exit_code']==0 and metadata['output']['sha256']==PINS['authority'] and metadata['output']['complete_reread_comparison'] is True,'Missing accepted complete metadata authority')
    require(authority['all806_input_bindings']==previous['accepted']['input_bindings']==ledger and len(ledger)==806,'Incomplete/changed original806 bindings')
    require(authority['source_report']['sha256']==PINS['report'] and authority['source_report']['bytes']==498049055 and authority['atlas_input_binding']=='1a404021b32f6c8f2ed91408a27e2894c18e82200150be91365db907c380e17e','Changed report/atlas INPUT binding')
    receipt=inputs['receipt']
    require(receipt['accepted'] is True and receipt['merged'] is True and receipt['head']=='205b6f2c6bfabaa26472b1f5fdedfaefe08ddcc9' and receipt['merge_sha']=='6429e8f6ade732fb169922e2869bb58690be3b03' and receipt['actual_current_HEAD_CI_all12_success'] is True and receipt['ci_run_id']==41884930105,'Accepted266 custody mismatch')
    require(receipt['E'] is None and receipt['physical_acceptance'] is False and receipt['final_report_sha256']==PINS['report'] and receipt['exact_remaining_targets']['sha256']==PINS['remaining'],'Predecessor receipt scope changed')
    require(authority['counts']['unique_contexts']==47 and len(authority['shared_contexts'])==47 and len(authority['row_headers'])==42 and len(authority['birth_roles'])==4 and authority['counts']['unknown_birth_obligations']==812,'Original40/terminal/child/birth context coverage changed')
    require(authority['targets']=={name:previous['accepted'][name] for name in ('area_targets','birth_targets','children')},'Original complete target/child inventory changed')
    for field in ('area_targets','birth_targets'):
        require([t for t in authority['targets'][field] if t['outcome']=='UNKNOWN']==inputs['remaining'][field],'Dropped original remaining/birth obligations')
    manifest=inputs['native_manifest'];index={row['role']:row for row in manifest['bundle_index']};bundle=Path(args.bundle_root).resolve()
    require(len(index)==len(manifest['bundle_index'])==789 and manifest['bundle_sha256']=='029bf54ce9abc296bff0f16bcd761298e8666d009415240a554522518ef38a3f','Accepted249 closed role index differs')
    def role(name,parse=True):
        row=index[name];path=Path(row['path'])
        require(not path.is_absolute() and '..' not in path.parts and ledger['role:'+name]==row['sha256'],'Unsafe/stale native role')
        path=(bundle/path).resolve();require(path.is_relative_to(bundle),'Native role escapes bundle')
        return read_checked(path,row['sha256'],watched,parse=parse)
    for name in index:
        if name.startswith('engine-source/'):role(name,False)
    native=role('native')
    require(native['version']==2 and native['loop_mode']==1 and len(native['bones'])==len(native['skin'])==53 and len(native['tracks'])==46,'Captured native denominator/loop policy changed')
    require(native['bones']==authority['native_bones'] and native['skin']==authority['native_true_skin_binds'] and native['tracks']==authority['native_tracks'],'Captured ancestry/default/rest/track/true-bind data changed')
    require([b['resolved_bone'] for b in native['skin']]==list(range(53)),'True bind mapping changed')
    for path,pin in native['input_hashes'].items():
        # The accepted helper exempts live project settings; its frozen role stays hash-bound.
        if path!='project.godot':require(index['resource:'+path]['sha256']==pin,'Captured native source-resource binding differs')
        role('resource:'+path,False)
    sources=[('tools/units3d/cavalry_march_phase.py',HELPER_SHA),('tools/units3d/check_cavalry_march_capture.py',NATIVE_SHA),
             ('tools/units3d/royal_native_arithmetic/prove.py',SCALAR_SHA),('tools/units3d/analyze_cavalry_matrix_boxes.py','02a91af95af913d553562740da30afa45912d46411a8446b38b0adfedf74c75f')]
    for path,pin in sources:read_checked(ROOT/path,pin,watched,parse=False)
    for file,key in [('capture.c','source_sha256'),('capture.gd','script_sha256')]:
        read_checked(ROOT/'tools/units3d/royal_native_arithmetic'/file,inputs['arithmetic_capture']['acquisition'][key],watched,parse=False)
    require(inputs['arithmetic_receipt']==authority['native_scalar_receipt'] and inputs['arithmetic_capture']==authority['native_scalar_capture'],'Accepted scalar profile/capture changed')
    require(len(previous['certificates'])==2910 and previous['work_plan']['parent_branch_visits']==2714 and previous['work_plan']['child_branch_visits']==196,'Original whole witness/job denominator differs')
    jobs=previous['certificates']
    for job_id,job in jobs.items():
        require(job_id==digest([job['certificate_sha256'],job['branch_index'],job['shared_transform_sha256']]) and job['shared_transform_sha256'] in authority['shared_contexts'],'Stale original saved witness identity')
    return {'native':native,'contexts':authority['shared_contexts'],'pairs':PAIRS,'jobs':jobs,
            'previous':previous,'authority':authority,'scalar_capture':inputs['arithmetic_capture'],
            'scalar_receipt':inputs['arithmetic_receipt'],'watched':watched,'input_pins':PINS,
            'source_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest()}


def finite_plan(packet):
    bones=packet['native']['bones'];contexts=len(packet['contexts']);nonroot=sum(b['parent']>=0 for b in bones)
    return {'contexts':contexts,'bones':len(bones),'tracks':len(packet['native']['tracks']),
        'local_global_records':contexts*len(bones),'FK_products':contexts*nonroot,'true_bind_products':contexts*8,
        'relative_pair_certificates':contexts*4,'saved_job_joins':len(packet['jobs']),
        'source_affine_nodes':{'multiply':36,'add':27},'analytic_product_bound_evaluations':contexts*(nonroot+12),
        'max_output_bytes':268435456,'existing_helper_limits':range_authority().LIMITS,
        'risk':'Exact rational bit growth and wall time are not forecasts. All cold reads/source/profile checks and finite proof/replay must fit original300. FTZ-closure failure is STOP; no widened fallback.'}



def check_range_budget(native,budget,scalar,ranges):
    require(budget.used<=ranges.LIMITS['float32_weight_values_total'] and len(budget.norm_records)<=47*len(native['bones']),'Existing native proof budget exhausted')
    branch_bound=47*8*sum(len(t['keys']) for t in native['tracks'] if t['type']==2)
    require(sum(len(v) for v in budget.norm_records.values())<=branch_bound,'Native sign/normalization branch cap exhausted')
    if hasattr(scalar,'work'):
        key_pairs=sum(len(t['keys'])-1 for t in native['tracks'] if t['type']==2 and t['interpolation']!=0)
        bound=ranges.LIMITS['continuous_boxes']*key_pairs*4
        require(scalar.work['weight_interval_compositions']<=bound and scalar.work['sine_ranges']<=3*bound+2*key_pairs and scalar.work['basic_interval_operations']<=6*bound,'Existing scalar composition budget exhausted')


def write_json(path,value,watched):
    path=Path(path).resolve();require(path not in {p for p,before in watched},'Output would replace an input')
    path.parent.mkdir(parents=True,exist_ok=True);total=0
    with path.open('x') as out:
        for part in json.JSONEncoder(sort_keys=True,separators=(',',':'),allow_nan=False).iterencode(packed(value)):
            total+=len(part.encode());require(total<=268435456,'Proof output exceeds original declared256MiB cap');out.write(part)
    return hashlib.sha256(path.read_bytes()).hexdigest()



def exact_proof_sizes(domains,audits):
    result={'fraction_count':0,'maximum_numerator_bits':0,'maximum_denominator_bits':0,'maximum_saved_integer_bits':0}
    def visit(value):
        if isinstance(value,Q):
            result['fraction_count']+=1
            result['maximum_numerator_bits']=max(result['maximum_numerator_bits'],abs(value.numerator).bit_length())
            result['maximum_denominator_bits']=max(result['maximum_denominator_bits'],value.denominator.bit_length())
        elif type(value) is int:result['maximum_saved_integer_bits']=max(result['maximum_saved_integer_bits'],abs(value).bit_length())
        elif isinstance(value,dict):
            for item in value.values():visit(item)
        elif isinstance(value,(tuple,list)):
            for item in value:visit(item)
    visit(domains);visit(audits)
    return result


def result_summary(packet,domains,audits):
    from collections import Counter
    return {'contexts':len(domains),'relations':sum(len(v['relations']) for v in domains.values()),
        'jobs':len(audits),'audit_statuses':dict(sorted(Counter(v['audit']['status'] for v in audits.values()).items())),
        'predecessor_area_classifications':packet['previous']['summary']['area_classifications'],
        'new_area_closures':0,'new_birth_closures':0,'physical_acceptance':False,'E':None}


def main():
    import argparse
    parser=argparse.ArgumentParser(description=__doc__);sub=parser.add_subparsers(dest='command',required=True)
    for command in ('compile','verify'):
        p=sub.add_parser(command)
        for name in PINS:p.add_argument('--'+name.replace('_','-'),type=Path,required=True)
        p.add_argument('--bundle-root',type=Path,required=True);p.add_argument('--out',type=Path,required=True)
        p.add_argument('--plan-out',type=Path,required=True)
        if command=='verify':p.add_argument('--result',type=Path,required=True)
    args=parser.parse_args()
    import datetime,os
    print(json.dumps({'pid':os.getpid(),'parent_pid':os.getppid(),'started_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'command':args.command}),flush=True)
    try:
        packet=load_inputs(args);plan=finite_plan(packet);write_json(args.plan_out,plan,packet['watched'])
        print(json.dumps({'finite_plan':plan},sort_keys=True),flush=True)
        ranges=range_authority();authority=rounding_authority()
        scalar=ranges.ScalarAuthority(packet['scalar_capture'],packet['scalar_receipt'],packet['native'],packet['authority']['input_binding']['platform_math'])
        scalar.binding.update(capture_file_sha256=PINS['arithmetic_capture'],receipt_file_sha256=PINS['arithmetic_receipt'])
        if args.command=='compile':
            domains=compile_domains(packet,ranges,scalar,authority);audits=audit_jobs(packet,domains)
            require(all(v['audit']['status']!='UNRESOLVED' for v in audits.values()),'Incomplete necessary relation coverage')
            result={'kind':'NECESSARY_RELATIVE_SKIN_DOMAIN_SAVED_POINT_AUDIT_ONLY','version':1,
                'input_pins':PINS,'source_sha256':packet['source_sha256'],'plan':plan,'domains':domains,'audits':audits,
                'target_audits':target_audits(packet['previous'],audits),'summary':result_summary(packet,domains,audits),'proof_sizes':exact_proof_sizes(domains,audits),'scalar_work':dict(scalar.work)}
        else:
            before=signature(args.result);raw=args.result.read_bytes()
            require(signature(args.result)==before,'Compiled result changed during cold read')
            require(len(raw)<=268435456,'Compiled result exceeds original declared256MiB cap')
            result=json.loads(raw);packet['watched'].append((args.result.resolve(),before))
            require(result['kind']=='NECESSARY_RELATIVE_SKIN_DOMAIN_SAVED_POINT_AUDIT_ONLY' and result['version']==1 and result['input_pins']==PINS and result['source_sha256']==packet['source_sha256'] and result['plan']==plan,'Changed sidecar source/input/plan binding')
            domains=decode_domains(result['domains']);audits=decode_audits(result['audits'])
            replay_domains_and_audits(packet,domains,audits,ranges,scalar,authority)
            require(result['target_audits']==target_audits(packet['previous'],audits) and result['summary']==result_summary(packet,domains,audits) and result['proof_sizes']==exact_proof_sizes(domains,audits) and result['scalar_work']==dict(scalar.work),'Target/audit/resource historical accounting changed')
            result={'status':'WHOLE_NECESSARY_DOMAIN_AND_SAVED_POINT_REPLAYED_NO_SHAPE_CLOSURE',
                    'result_sha256':hashlib.sha256(raw).hexdigest(),'summary':result['summary'],'input_pins':PINS}
        unchanged(packet['watched']);out_sha=write_json(args.out,result,packet['watched']);unchanged(packet['watched'])
        print(json.dumps({'out_sha256':out_sha,'summary':result['summary']},sort_keys=True));return 0
    except (ValueError,KeyError,OSError,MemoryError,TypeError) as error:
        print(json.dumps({'status':'STOP_NO_AUTHORITY_OR_RESOURCE','reason':str(error)}));return 2


if __name__=='__main__':raise SystemExit(main())
