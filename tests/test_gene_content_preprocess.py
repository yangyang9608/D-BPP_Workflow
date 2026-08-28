import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ANN = ROOT / "upstream" / "annotation_curation"
ANN_SCRIPTS = ANN / "scripts"
GC = ROOT / "upstream" / "gene_content_tree"
GC_SCRIPTS = GC / "scripts"


class GeneContentPreprocessTests(unittest.TestCase):
    def run_py(self, script_path, *args):
        return subprocess.run(
            [sys.executable, str(script_path), *map(str, args)],
            check=True,
            text=True,
            capture_output=True,
        )

    def test_gene_count_to_binary_matrix(self):
        with tempfile.TemporaryDirectory() as td:
            prefix = Path(td) / "matrix"
            self.run_py(
                GC_SCRIPTS / "build_gene_content_matrix.py",
                "--gene-count", GC / "example" / "Orthogroups.GeneCount.tsv",
                "--out-prefix", prefix,
            )
            lines = Path(str(prefix) + ".phy").read_text().strip().splitlines()
            self.assertEqual(lines[0], "4 7")  # universal OG removed
            self.assertEqual(lines[1], "SpeciesA 1101001")
            summary = Path(str(prefix) + ".summary.tsv").read_text()
            self.assertIn("dropped_universal\t1", summary)


    def test_gff_to_cds_bed_and_cluster_selection(self):
        with tempfile.TemporaryDirectory() as td:
            td = Path(td)
            gff = td / "x.gff3"
            gff.write_text(
                "##gff-version 3\n"
                "chr1\tx\tCDS\t101\t150\t.\t+\t0\tID=c1;Parent=t1\n"
                "chr1\tx\tCDS\t201\t250\t.\t+\t0\tID=c2;Parent=t1\n"
                "chr1\tx\tCDS\t140\t230\t.\t+\t0\tID=c3;Parent=t2\n"
                "chr1\tx\tCDS\t400\t460\t.\t-\t0\tID=c4;Parent=t3\n"
            )
            bed = self.run_py(ANN_SCRIPTS / "gff_to_cds_bed.py", "--gff", gff).stdout
            self.assertIn("chr1\t100\t250\tt1\t100\t+", bed)
            clustered = td / "clustered.bed"
            clustered.write_text(
                "chr1\t100\t250\tt1\t100\t+\t1\n"
                "chr1\t139\t230\tt2\t91\t+\t1\n"
                "chr1\t399\t460\tt3\t61\t-\t2\n"
            )
            keep = td / "keep.txt"
            summary = td / "summary.tsv"
            self.run_py(
                ANN_SCRIPTS / "select_cluster_representatives.py",
                "--clustered-bed", clustered,
                "--keep-list", keep,
                "--summary", summary,
            )
            self.assertEqual(keep.read_text().splitlines(), ["t1", "t3"])

    def test_cds_protein_filtering_and_prefix(self):
        with tempfile.TemporaryDirectory() as td:
            td = Path(td)
            cds = td / "x.cds.fa"
            pep = td / "x.faa"
            cds.write_text(">t1\nATGAAATAA\n>t2\nATGAAAAA\n>t3\nATGAAATAG\n")
            pep.write_text(">t1\nMK*\n>t2\nMK\n>t3\nM*K\n")
            out_cds = td / "out.cds.fa"
            out_pep = td / "out.faa"
            idmap = td / "map.tsv"
            summary = td / "summary.tsv"
            self.run_py(
                ANN_SCRIPTS / "filter_cds_protein.py",
                "--cds", cds,
                "--protein", pep,
                "--out-cds", out_cds,
                "--out-protein", out_pep,
                "--id-map", idmap,
                "--summary", summary,
                "--prefix", "Sp",
            )
            self.assertIn(">Sp|t1", out_pep.read_text())
            self.assertNotIn("Sp|t2", out_pep.read_text())
            self.assertNotIn("Sp|t3", out_pep.read_text())
            s = summary.read_text()
            self.assertIn("kept\t1", s)
            self.assertIn("cds_not_divisible_by_3\t1", s)
            self.assertIn("internal_stop\t1", s)


if __name__ == "__main__":
    unittest.main()
