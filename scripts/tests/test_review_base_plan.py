import copy
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('review', Path(__file__).parents[1] / 'review_base_plan.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def example():
    return {'format_version': '1.2', 'terraform_version': '1.15.9', 'complete': True,
            'timestamp': 'first run', 'variables': {'environment': {'value': 'hom'}},
            'resource_changes': [{'address': 'aws_eks_access_entry.pipeline["base"]',
                                  'type': 'aws_eks_access_entry', 'mode': 'managed',
                                  'change': {'actions': ['create'], 'before': None,
                                             'after': {'principal_arn': 'base-hom'},
                                             'after_unknown': {'id': True}}}]}


class ReviewTests(unittest.TestCase):
    def test_timestamp_and_data_refresh_do_not_invalidate_approval(self):
        plan = example()
        second = copy.deepcopy(plan)
        second['timestamp'] = 'second run'
        second['resource_changes'].append({'address': 'data.aws_caller_identity.current', 'mode': 'data', 'change': {'actions': ['read']}})
        self.assertEqual(module.review(plan)['sha256'], module.review(second)['sha256'])

    def test_changed_identity_unknowns_outputs_or_variables_invalidate_approval(self):
        for path in ['identity', 'unknowns', 'outputs', 'variables', 'drift']:
            with self.subTest(path=path):
                plan = example()
                if path == 'identity': plan['resource_changes'][0]['change']['after']['principal_arn'] = 'base-prd'
                if path == 'unknowns': plan['resource_changes'][0]['change']['after_unknown']['id'] = False
                if path == 'outputs': plan['output_changes'] = {'secret': {'actions': ['update'], 'after': 'never-print'}}
                if path == 'variables': plan['variables']['environment']['value'] = 'prd'
                if path == 'drift': plan['resource_drift'] = copy.deepcopy(plan['resource_changes'])
                self.assertNotEqual(module.review(example())['sha256'], module.review(plan)['sha256'])

    def test_replacement_is_destructive(self):
        plan = example()
        plan['resource_changes'][0]['change']['actions'] = ['delete', 'create']
        self.assertTrue(module.review(plan)['destructive'])

    def test_new_cluster_requires_explicit_creator_setting(self):
        for flag in [True, None, False]:
            with self.subTest(flag=flag):
                plan = example()
                item = plan['resource_changes'][0]
                item['type'] = 'aws_eks_cluster'
                item['change']['after'] = {'access_config': [{'bootstrap_cluster_creator_admin_permissions': flag}]}
                if flag is False: self.assertTrue(module.review(plan)['creates_cluster'])
                else:
                    with self.assertRaises(ValueError): module.review(plan)

    def test_noop_and_output_only_changes(self):
        plan = example()
        plan['resource_changes'][0]['change']['actions'] = ['no-op']
        self.assertFalse(module.review(plan)['has_changes'])
        plan['output_changes'] = {'name': {'actions': ['update']}}
        self.assertTrue(module.review(plan)['has_changes'])

    def test_incomplete_plan_is_refused(self):
        plan = example()
        plan['complete'] = False
        with self.assertRaises(ValueError): module.review(plan)

    def test_report_does_not_expose_values(self):
        result = module.review(example())
        self.assertNotIn('principal_arn', str(result))
        self.assertNotIn('base-hom', str(result))


if __name__ == '__main__': unittest.main()
