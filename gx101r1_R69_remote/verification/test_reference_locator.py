import unittest

from Build_HeatDriveECC_ReferenceLocator import REFERENCES, identity, normalize, page_anchor


class ReferenceLocatorTests(unittest.TestCase):
    def test_local_corpus_distinguishes_auxiliary_author_and_quantitative_contract(self):
        self.assertEqual(len(REFERENCES),10)
        self.assertEqual(sum(r[5] for r in REFERENCES),9)
        self.assertEqual([r[0] for r in REFERENCES if r[4]=='primary_2019_quantitative_contract'],['Q01'])
        self.assertEqual(REFERENCES[-1][3],['Dong Luo','Yinshan Feng','Parmesh Verma'])
        self.assertFalse(REFERENCES[-1][5])

    def test_line_wrapped_doi_is_not_a_different_reference(self):
        identity('Suxin Qian https://doi.org/10.1016/j.energy.2017.09.1 16',
                 '10.1016/j.energy.2017.09.116',['Suxin Qian'],True)
        with self.assertRaises(ValueError):identity('Suxin Qian 10.1016/wrong','10.1016/right',['Qian'],True)

    def test_title_page_authorship_not_a_body_citation(self):
        identity('Dong Luo, Yinshan Feng, Parmesh Verma',None,['Dong Luo','Verma'],False)
        identity('Dong Luo, Yinshan Feng, Parmesh Verma. Introduction: Qian et al. proposed a cycle.',
                 None,['Dong Luo','Verma'],False)
        with self.assertRaises(ValueError):identity('Dong Luo',None,['Dong Luo'],True)

    def test_pdf_page_and_printed_page_are_independently_checked(self):
        self.assertTrue(page_anchor(' 95\nChapter 4: Novel Thermo-wave Heat Recovery',
            ['Chapter 4','Thermo-wave'],95)['anchor_match'])
        with self.assertRaises(ValueError):page_anchor('64 Chapter 3: Cycle Analysis',['Chapter 4'],95)
        with self.assertRaises(ValueError):page_anchor('95 Chapter 4',['Chapter 4'],122)

    def test_dissertation_anchors_use_actual_local_pages(self):
        self.assertEqual([(n,printed) for n,_,printed in REFERENCES[8][6]],[(91,64),(122,95),(158,131)])
        self.assertEqual(normalize('efﬁciency\n heat recovery'),'efficiency heat recovery')

    def test_energy_equations_precede_the_full_page_system_figure(self):
        self.assertEqual(REFERENCES[0][6][0][0],3)
        self.assertEqual(REFERENCES[0][6][1][0],4)
        self.assertEqual(REFERENCES[0][6][2][0],5)


if __name__=='__main__':unittest.main()
