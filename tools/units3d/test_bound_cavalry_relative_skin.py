"""Exact algebra and hostile native-operation controls; no real dataset loaded."""
from fractions import Fraction as Q
import importlib.util
from pathlib import Path
import unittest

MODULE = Path(__file__).with_name('bound_cavalry_relative_skin.py')
if MODULE.exists():
    spec = importlib.util.spec_from_file_location('relative_skin_under_test', MODULE)
    skin = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(skin)
else:
    skin = None


def affine_x(scale=1, origin=0):
    return tuple(tuple(map(Q,row)) for row in ((scale,0,0,origin),(0,1,0,0),(0,0,1,0),(0,0,0,1)))


def zero(): return tuple((Q(0),)*4 for _ in range(4))


def error_x(scale=0, origin=0):
    return ((Q(scale),Q(0),Q(0),Q(origin)),)+(zero()[1:])


def binary32(value, mode='nearest', output_ftz=False):
    """Independent exact IEEE oracle, including directed ties and subnormals."""
    value=Q(value)
    if not value:return value
    sign=1 if value>0 else -1
    absolute=abs(value)
    exponent=absolute.numerator.bit_length()-absolute.denominator.bit_length()
    exponent-=absolute<Q(2)**exponent
    unit=Q(2)**max(exponent-23,-149)
    exact=absolute/unit;integer=exact.numerator//exact.denominator
    fraction=exact-integer
    up=(mode=='up' and sign>0) or (mode=='down' and sign<0)
    if mode=='nearest':up=fraction>Q(1,2) or fraction==Q(1,2) and integer%2==1
    rounded=sign*(integer+(bool(fraction) and up))*unit
    return Q(0) if output_ftz and abs(rounded)<Q(2)**-126 else rounded


def native_affine(a,b,mode,input_ftz,output_ftz,first_fma,last_fma):
    tiny=Q(2)**-126
    flush=lambda x:Q(0) if input_ftz and abs(x)<tiny else x
    rnd=lambda x:binary32(x,mode,output_ftz)
    multiply=lambda x,y:rnd(flush(x)*flush(y))
    add=lambda x,y:rnd(flush(x)+flush(y))
    fma=lambda x,y,z:rnd(flush(x)*flush(y)+flush(z))
    result=[]
    for axis in range(3):
        row=[]
        for column in range(4):
            x=[a[axis][k] for k in range(3)];y=[b[k][column] for k in range(3)]
            if first_fma==0:partial=fma(x[0],y[0],multiply(x[1],y[1]))
            elif first_fma==1:partial=fma(x[1],y[1],multiply(x[0],y[0]))
            else:partial=add(multiply(x[0],y[0]),multiply(x[1],y[1]))
            value=fma(x[2],y[2],partial) if last_fma else add(partial,multiply(x[2],y[2]))
            row.append(add(value,a[axis][3]) if column==3 else value)
        result.append(tuple(row))
    return tuple(result)+((Q(0),Q(0),Q(0),Q(1)),)


class RelativeSkinTests(unittest.TestCase):
    def setUp(self):
        self.assertIsNotNone(skin,'The relative-skin domain module is not implemented')

    def test_hand_computed_inverse_and_noncommutative_order(self):
        gp,lc,bp,bc=affine_x(1,10),affine_x(2,3),affine_x(1,1),affine_x(1,-4)
        c=skin.matmul(skin.matmul(skin.affine_inverse(bp),lc),bc)
        self.assertEqual(c,affine_x(2,-6))
        self.assertEqual(skin.matmul(skin.matmul(gp,bp),c),skin.matmul(skin.matmul(gp,lc),bc))
        self.assertNotEqual(skin.matmul(skin.matmul(bp,lc),bc),c)
        self.assertNotEqual(skin.matmul(skin.matmul(lc,skin.affine_inverse(bp)),bc),c)

    def test_hand_computed_all_three_residual_terms_and_signs(self):
        gp,lc,bp,bc=affine_x(1,10),affine_x(2,3),affine_x(1,1),affine_x(1,-4)
        c=affine_x(2,-6);dp,dg,dc=error_x(Q(1,4)),error_x(origin=Q(1,2)),error_x(origin=-Q(1,8))
        sp=skin.matadd(skin.matmul(gp,bp),dp)
        sc=skin.matadd(skin.matmul(skin.matadd(skin.matmul(gp,lc),dg),bc),dc)
        residual=skin.transport_residual(dp,dg,dc,bc,c)
        self.assertEqual(residual,error_x(-Q(1,2),Q(15,8)))
        self.assertEqual(sc,affine_x(2,Q(43,8)))
        self.assertEqual(skin.matadd(skin.matmul(sp,c),residual),sc)
        self.assertNotEqual(skin.matadd(skin.matmul(dg,bc),dc),residual)

    def test_excludes_only_the_saved_point_and_keeps_valid_or_wider_case(self):
        relation={'C':skin.point_box(affine_x(2,-6)),'R':skin.point_box(zero())}
        bad=skin.audit_point(affine_x(1,11),affine_x(2,6),relation)
        self.assertEqual(bad['status'],'THIS_WITNESS_EXCLUDED_BY_NATIVE_RELATION')
        self.assertTrue(skin.replay_separation(affine_x(1,11),affine_x(2,6),relation,bad))
        good=skin.audit_point(affine_x(1,11),affine_x(2,5),relation)
        self.assertEqual(good['status'],'NOT_EXCLUDED_BY_THIS_BOUND')
        wide=skin.point_box(affine_x(2,-6));wide[0][3]=(Q(-7),Q(-5))
        self.assertEqual(skin.audit_point(affine_x(1,11),affine_x(2,6),{'C':wide,'R':relation['R']})['status'],'NOT_EXCLUDED_BY_THIS_BOUND')

    def test_singular_and_nonaffine_binds_fail(self):
        with self.assertRaises(ValueError):skin.affine_inverse(affine_x(0))
        malformed=[list(row) for row in affine_x()];malformed[3][3]=0
        with self.assertRaises(ValueError):skin.affine_inverse(malformed)

    def test_native_error_covers_every_ieee_fma_and_ftz_fixture(self):
        authority=skin.rounding_authority()
        fixtures=[
            (affine_x(Q(3,2),Q(7,4)),affine_x(Q(5,4),Q(-9,8))),
            (affine_x(Q(2)**-127,Q(2)**-130),affine_x(Q(2)**90,Q(2)**80)),
            (((Q(1),Q(-1),Q(2)**-127,Q(7,8)),(Q(-3,2),Q(1,4),Q(5,8),Q(-2)),(Q(1,8),Q(2),Q(-1),Q(3)),(Q(0),Q(0),Q(0),Q(1))),
             ((Q(1),Q(1),Q(3,8),Q(5,16)),(Q(1),Q(1),Q(-3,8),Q(-5,16)),(Q(2)**90,Q(-2)**1,Q(3),Q(1)),(Q(0),Q(0),Q(0),Q(1))))]
        for a,b in fixtures:
            relation=skin.native_product_error(skin.point_box(a),skin.point_box(b),authority)
            exact=skin.matmul(a,b)
            for mode in ('nearest','zero','up','down'):
                for input_ftz in (False,True):
                    for output_ftz in (False,True):
                        for first in (None,0,1):
                            for last in (False,True):
                                actual=native_affine(a,b,mode,input_ftz,output_ftz,first,last)
                                for i in range(4):
                                    for j in range(4):
                                        self.assertLessEqual(abs(actual[i][j]-exact[i][j]),relation['absolute'][i][j])
            self.assertEqual(relation['source_nodes'],{'multiply':36,'add':27})
            self.assertEqual(relation['absolute'][3],[Q(0)]*4)

    def test_tiny_input_times_large_is_not_a_result_only_flush_bound(self):
        authority=skin.rounding_authority();a,b=affine_x(Q(2)**-127),affine_x(Q(2)**90)
        error=skin.native_product_error(skin.point_box(a),skin.point_box(b),authority)
        actual=native_affine(a,b,'nearest',True,False,None,False)
        difference=abs(actual[0][0]-skin.matmul(a,b)[0][0])
        self.assertGreater(difference,authority.rnd(Q(2)**-37,24))
        self.assertGreaterEqual(error['absolute'][0][0],difference)

    def test_constraint_replay_detects_residual_and_outward_tampering(self):
        import copy
        gp,lc,bp,bc=map(skin.point_box,[affine_x(1,10),affine_x(2,3),affine_x(1,1),affine_x(1,-4)])
        record=skin.compile_constraint(gp,lc,affine_x(1,1),affine_x(1,-4),skin.rounding_authority())
        self.assertTrue(skin.replay_constraint(gp,lc,affine_x(1,1),affine_x(1,-4),record,skin.rounding_authority()))
        for field in ('Dp','Dg','Dc','R'):
            changed=copy.deepcopy(record);changed[field][0][0]=(Q(0),Q(0))
            with self.assertRaises(ValueError):skin.replay_constraint(gp,lc,affine_x(1,1),affine_x(1,-4),changed,skin.rounding_authority())
        changed=copy.deepcopy(record);lo,hi=changed['C'][0][3];changed['C'][0][3]=(lo+1,hi+1)
        with self.assertRaises(ValueError):skin.replay_constraint(gp,lc,affine_x(1,1),affine_x(1,-4),changed,skin.rounding_authority())


    def test_only_pure_range_dependencies_are_loaded(self):
        self.assertTrue(hasattr(skin,'range_authority'),'Pure range loader is not implemented')
        ranges=skin.range_authority()
        self.assertFalse(hasattr(ranges,'surface_span_box'))
        self.assertFalse(hasattr(ranges.native,'surface_points'))
        self.assertFalse(hasattr(ranges.scalar,'acquire'))
        self.assertFalse(hasattr(ranges.scalar,'run'))

    def test_local_range_primitives_stop_on_uncovered_ftz_inputs(self):
        self.assertTrue(hasattr(skin,'range_authority'),'Pure range loader is not implemented')
        ranges=skin.range_authority();box=ranges.native.Float32Box
        tiny=2.0**-127
        with self.assertRaisesRegex(ValueError,'FTZ'):
            box(tiny)*box(2.0**90)
        admitted=box(-tiny,tiny)*box(2.0**90)
        self.assertLessEqual(float(admitted.lo),0)
        self.assertGreaterEqual(float(admitted.hi),0)


    def small_packet(self):
        def flat(value):return [float(v) for row in value[:3] for v in row]
        bones=[]
        for index,position,scale in [(0,10,1),(1,3,2)]:
            bones.append({'name':'parent' if index==0 else 'child','parent':index-1,
                'default_position':[position,0,0],'default_rotation':[0,0,0,1],
                'rest_rotation':[0,0,0,1],'default_scale':[scale,1,1],'rest':flat(affine_x(scale,position))})
        native={'bones':bones,'tracks':[],'length':0.5,'skin':[
            {'name':'parent','resolved_bone':0,'pose':flat(affine_x(1,1))},
            {'name':'child','resolved_bone':1,'pose':flat(affine_x(1,-4))}]}
        low=[flat(affine_x(1,11)),flat(affine_x(2,5))]
        high=[flat(affine_x(1,11)),flat(affine_x(2,7))]
        context={'method':'fixture','seconds':[0.0,0.25],'source_sha256':'0'*64,
            'matrix_interval':[[[row[i:i+4] for i in (0,4,8)] for row in side] for side in (low,high)]}
        context_id=skin.digest(context);source='a'*64
        variables=[[joint,column] for joint in (0,1) for column in range(4)]
        wp,wc=affine_x(1,11),affine_x(2,6)
        assignment=[[[v.numerator,v.denominator] for row in (wp[axis],wc[axis]) for v in row] for axis in range(3)]
        job={'certificate_sha256':source,'branch_index':0,'shared_transform_sha256':context_id,
            'variables':variables,'unused_matrix_entries':'exact_interval_midpoint',
            'proof':{'status':'REFERENCE_BOX_DEGENERATE','assignment':assignment}}
        return {'native':native,'contexts':{context_id:context},'pairs':[[0,1]],
            'jobs':{skin.digest([source,0,context_id]):job}}

    def test_small_native_fixture_compiles_all_contexts_and_replays_point_audit(self):
        self.assertTrue(hasattr(skin,'compile_domains'),'Whole-domain fixture functions are not implemented')
        packet=self.small_packet();domains=skin.compile_domains(packet,skin.range_authority(),object(),skin.rounding_authority())
        audits=skin.audit_jobs(packet,domains)
        self.assertEqual(len(domains),1)
        self.assertEqual(next(iter(audits.values()))['audit']['status'],skin.EXCLUDED)
        self.assertTrue(skin.replay_domains_and_audits(packet,domains,audits,skin.range_authority(),object(),skin.rounding_authority()))

    def test_single_bind_and_nondegenerate_jobs_keep_their_original_accounting(self):
        self.assertTrue(hasattr(skin,'compile_domains'),'Whole-domain fixture functions are not implemented')
        import copy
        packet=self.small_packet();original=next(iter(packet['jobs'].values()))
        single=copy.deepcopy(original);single['variables']=[[0,column] for column in range(4)]
        single['proof']['assignment']=[row[:4] for row in single['proof']['assignment']]
        nondeg=copy.deepcopy(original);nondeg['proof']={'status':'REFERENCE_BOX_NONDEGENERATE'}
        packet['jobs']={'single':single,'nondeg':nondeg}
        domains=skin.compile_domains(packet,skin.range_authority(),object(),skin.rounding_authority())
        audits=skin.audit_jobs(packet,domains)
        self.assertEqual(audits['single']['audit']['status'],'NOT_APPLICABLE_SINGLE_BIND')
        self.assertEqual(audits['nondeg']['audit']['status'],'ORIGINAL_NONDEGENERATE_RESULT_PRESERVED')
        self.assertEqual(audits['nondeg']['old_status'],'REFERENCE_BOX_NONDEGENERATE')

    def test_changed_context_hierarchy_bind_and_missing_denominator_fail_closed(self):
        self.assertTrue(hasattr(skin,'compile_domains'),'Whole-domain fixture functions are not implemented')
        import copy
        packet=self.small_packet()
        for change in ('context','hierarchy','bind'):
            altered=copy.deepcopy(packet)
            if change=='context':next(iter(altered['contexts'].values()))['seconds'][1]=0.3
            if change=='hierarchy':altered['native']['bones'][1]['parent']=-1
            if change=='bind':altered['native']['skin'][0]['resolved_bone']=1
            with self.assertRaises(ValueError):skin.compile_domains(altered,skin.range_authority(),object(),skin.rounding_authority())
        domains=skin.compile_domains(packet,skin.range_authority(),object(),skin.rounding_authority())
        altered=copy.deepcopy(packet);next(iter(altered['jobs'].values()))['proof']['assignment'][0][0]=[1]
        with self.assertRaises(ValueError):skin.audit_jobs(altered,domains)


    def test_serialized_domain_replays_without_losing_any_rational_denominator(self):
        self.assertTrue(hasattr(skin,'decode_domains'),'Domain codec is not implemented')
        import json
        packet=self.small_packet();domains=skin.compile_domains(packet,skin.range_authority(),object(),skin.rounding_authority())
        audits=skin.audit_jobs(packet,domains)
        decoded=skin.decode_domains(json.loads(json.dumps(skin.packed(domains))))
        self.assertEqual(decoded,domains)
        self.assertTrue(skin.replay_domains_and_audits(packet,decoded,audits,skin.range_authority(),object(),skin.rounding_authority()))

    def test_missing_branch_relation_and_changed_strict_point_do_not_replay(self):
        import copy
        packet=self.small_packet();domains=skin.compile_domains(packet,skin.range_authority(),object(),skin.rounding_authority())
        audits=skin.audit_jobs(packet,domains)
        altered=copy.deepcopy(domains);next(iter(altered.values()))['relations'].clear()
        with self.assertRaises(ValueError):skin.replay_domains_and_audits(packet,altered,audits,skin.range_authority(),object(),skin.rounding_authority())
        altered=copy.deepcopy(audits);next(iter(altered.values()))['audit']['separation']['value']+=1
        with self.assertRaises(ValueError):skin.replay_domains_and_audits(packet,domains,altered,skin.range_authority(),object(),skin.rounding_authority())

    def test_source_pin_and_invalid_exact_endpoint_are_rejected(self):
        import tempfile
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory)/'changed.py';path.write_text('not the accepted source')
            with self.assertRaisesRegex(ValueError,'source changed'):skin.source_bytes(path,skin.HELPER_SHA)
        for value in (float('nan'),float('inf'),True):
            with self.assertRaises(ValueError):skin.exact(value)
        with self.assertRaises(ValueError):skin.interval_box([[(Q(1),Q(0))]*4]*4)
        self.assertEqual(skin.audit_point(affine_x(),affine_x(),None),{'status':'UNRESOLVED'})


    def test_file_custody_rejects_stale_profile_and_changes_during_run(self):
        self.assertTrue(hasattr(skin,'read_checked'),'Custody reader is not implemented')
        import hashlib,tempfile
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory)/'profile.json';path.write_bytes(b'{"profile":"fixture"}')
            expected=hashlib.sha256(path.read_bytes()).hexdigest();watched=[]
            self.assertEqual(skin.read_checked(path,expected,watched),{'profile':'fixture'})
            with self.assertRaises(ValueError):skin.read_checked(path,expected,[],size=1)
            path.write_bytes(b'{"profile":"changed"}')
            with self.assertRaises(ValueError):skin.read_checked(path,expected,[])
            with self.assertRaises(ValueError):skin.unchanged(watched)

    def test_serialized_exclusion_has_independent_strict_replay(self):
        self.assertTrue(hasattr(skin,'decode_audits'),'Witness codec is not implemented')
        import json
        packet=self.small_packet();domains=skin.compile_domains(packet,skin.range_authority(),object(),skin.rounding_authority())
        audits=skin.audit_jobs(packet,domains)
        decoded=skin.decode_audits(json.loads(json.dumps(skin.packed(audits))))
        self.assertEqual(decoded,audits)
        self.assertTrue(skin.replay_domains_and_audits(packet,domains,decoded,skin.range_authority(),object(),skin.rounding_authority()))

    def test_parent_only_children_and_positive_area_birth_stay_historical(self):
        self.assertTrue(hasattr(skin,'target_audits'),'Target accounting is not implemented')
        previous={'area_dispositions':[{'classification':'PARENT_OBSTRUCTED_CHILD_COVER_NONDEGENERATE','parent_jobs':['p'],'child_jobs':[['a'],['b']]}],
                  'birth_dispositions':[{'area_classification':'ACCEPTED_POSITIVE_AREA_DOT_UNRESOLVED','parent_jobs':None,'child_jobs':None}]}
        audits={'p':{'audit':{'status':skin.EXCLUDED}},'a':{'audit':{'status':'ORIGINAL_NONDEGENERATE_RESULT_PRESERVED'}},'b':{'audit':{'status':'ORIGINAL_NONDEGENERATE_RESULT_PRESERVED'}}}
        output=skin.target_audits(previous,audits)
        self.assertEqual(output['area'][0]['predecessor'],previous['area_dispositions'][0])
        self.assertEqual(output['area'][0]['children'],[['ORIGINAL_NONDEGENERATE_RESULT_PRESERVED'],['ORIGINAL_NONDEGENERATE_RESULT_PRESERVED']])
        self.assertEqual(output['birth'][0]['predecessor'],previous['birth_dispositions'][0])
        self.assertIsNone(output['birth'][0]['parent'])


    def test_fixed_key_quaternion_branches_survive_full_json_replay(self):
        import json
        packet=self.small_packet()
        packet['native']['tracks']=[{'path':'Skeleton:'+bone['name'],'type':2,'keys':[{'time':0.0,'value':[0,0,0,1]}],
            'interpolation':1,'loop_wrap':True,'enabled':True,'compressed':False} for bone in packet['native']['bones']]
        domains=skin.compile_domains(packet,skin.range_authority(),object(),skin.rounding_authority())
        self.assertEqual(len(next(iter(domains.values()))['local_certificates']),2)
        decoded=skin.decode_domains(json.loads(json.dumps(skin.packed(domains))))
        audits=skin.audit_jobs(packet,decoded)
        self.assertTrue(skin.replay_domains_and_audits(packet,decoded,audits,skin.range_authority(),object(),skin.rounding_authority()))


    def test_full_affine_bind_inverse_keeps_shear_scale_and_origin(self):
        binding=((2,1,0,1),(0,3,1,2),(0,0,4,3),(0,0,0,1))
        expected=((Q(1,2),-Q(1,6),Q(1,24),-Q(7,24)),(0,Q(1,3),-Q(1,12),-Q(5,12)),(0,0,Q(1,4),-Q(3,4)),(0,0,0,1))
        self.assertEqual(skin.affine_inverse(binding),expected)

    def test_changed_saved_point_and_missing_branch_context_do_not_replay(self):
        import copy
        packet=self.small_packet();domains=skin.compile_domains(packet,skin.range_authority(),object(),skin.rounding_authority());audits=skin.audit_jobs(packet,domains)
        changed=copy.deepcopy(packet);next(iter(changed['jobs'].values()))['proof']['assignment'][0][7]=[13,2]
        with self.assertRaises(ValueError):skin.replay_domains_and_audits(changed,domains,audits,skin.range_authority(),object(),skin.rounding_authority())
        changed=copy.deepcopy(packet);changed['contexts'].clear()
        with self.assertRaises(ValueError):skin.replay_domains_and_audits(changed,domains,audits,skin.range_authority(),object(),skin.rounding_authority())

    def test_existing_scalar_budget_is_preserved_and_fails_closed(self):
        from types import SimpleNamespace
        packet=self.small_packet();ranges=skin.range_authority();budget=ranges.Budget(arithmetic=object())
        scalar=SimpleNamespace(work={'weight_interval_compositions':0,'sine_ranges':0,'basic_interval_operations':0})
        skin.check_range_budget(packet['native'],budget,scalar,ranges)
        scalar.work['basic_interval_operations']=1
        with self.assertRaises(ValueError):skin.check_range_budget(packet['native'],budget,scalar,ranges)


    def test_pure_dependency_closure_has_no_unbound_runtime_global(self):
        import builtins,dis,types
        ranges=skin.range_authority();missing=[]
        def check(code,namespace):
            for instruction in dis.get_instructions(code):
                if instruction.opname in ('LOAD_GLOBAL','LOAD_NAME') and instruction.argval not in namespace and instruction.argval not in vars(builtins):
                    missing.append((code.co_name,instruction.argval))
            for value in code.co_consts:
                if isinstance(value,types.CodeType):check(value,namespace)
        for module in (ranges,ranges.native,ranges.scalar):
            for value in vars(module).values():
                if isinstance(value,types.FunctionType) and value.__module__==module.__name__:check(value.__code__,value.__globals__)
                elif isinstance(value,type) and value.__module__==module.__name__:
                    for method in vars(value).values():
                        if isinstance(method,(classmethod,staticmethod)):method=method.__func__
                        if isinstance(method,types.FunctionType):check(method.__code__,method.__globals__)
        self.assertEqual(missing,[])


if __name__=='__main__':unittest.main()
