# Optional upstream workflows

D-BPP itself begins with candidate species-tree backbones plus aligned loci or a VCF. The `upstream/` directory provides optional utilities for users who want to construct a gene-family-content backbone from genome assemblies and protein-coding annotations before running the core D-BPP workflow.

The upstream workflow is intentionally split into two independent modules:

1. [`annotation_curation/`](annotation_curation/) — genome annotation and coding-sequence curation, ending in curated proteomes;
2. [`gene_content_tree/`](gene_content_tree/) — orthogroup inference, binary gene-content matrix construction, and species-tree inference from curated proteomes.

The modules can be used together, or the second module can start from independently curated proteomes. Neither module is required by D-BPP, and D-BPP can evaluate candidate backbone trees inferred from sequence data, other phylogenomic methods, or prior literature.

Article-specific robustness analyses are intentionally not included in the public workflow. The repository provides reusable backbone-construction steps rather than manuscript-specific simulation or perturbation procedures.
