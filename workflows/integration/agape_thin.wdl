version 1.0

# The agape_thin.wdl is to run smrtcells first, followed by samples/hifiasm/cohort in parallel using new structs, designed by Charlie Bi
# This new workflow is to simplify input-wdl.json, an easy version of trial.wdl
#
# This entry workflow calls a set of sub-workflows using new structs defined in common/struct.wdl

import "../smrtcells/smrtcells.agape.wdl"
import "../sample/sample.agape.wdl"
import "../fasta/fasta_agape.wdl"
import "../cohort/cohort.wdl"
import "../common/structs.wdl"
import "../hifiasm/sample_hifiasm.cohort.wdl"
import "../hifiasm/trio_hifiasm.cohort.wdl"

workflow agape {
  input {
    String cohort_name
    IndexedData reference

    File regions_file

    Array[PacBioSampInfo] pacbio_info
    Boolean ubam_bool
    String ubam_postfix
    Int kmer_length

    Array[String] parents_list

    File tr_bed
    File chr_lengths

    File hpoannotations
    File hpoterms
    File hpodag
    File gff
    File ensembl_to_hgnc
    File js
    File lof_lookup
    File gnomad_af
    File hprc_af
    File allyaml
    File ped
    File clinvar_lookup

    String pb_conda_image
    String deepvariant_image
    String glnexus_image

    File ref_modimers
    
    Boolean run_jellyfish = false   #default is to NOT run jellyfish
    Boolean trioeval = false        #default is to NOT run trioeval
    Boolean triobin = true          #default is to run triobin

    File tg_list
    File tg_bed
    File score_matrix
    LastIndexedData last_reference

  }

  Array[String] regions = read_lines(regions_file)

  scatter (samp in pacbio_info) {
    scatter (movie in samp.movies) {
       SmrtcellInfo smrtcell = object { 
	  name: "~{movie}", 
	  path: "~{samp.path}/~{movie}.~{ubam_postfix}", 
	  isUbam: ubam_bool 
       }
    }
  }
  Array[Array[SmrtcellInfo]] smrtcells = smrtcell

  Int num_samples = length(pacbio_info)
  scatter (n in range(num_samples)) {
    SampleInfo sample_info = object { 
	  name: "~{pacbio_info[n].name}", 
	  affected: pacbio_info[n].affected, 
	  parents: pacbio_info[n].parents, 
	  smrtcells: smrtcells[n] 
	}
  }
  Array[SampleInfo] cohort_info = sample_info

  #call smrtcells/smrtcells.agape.wdl
  call smrtcells.agape.smrtcells_cohort {
    input:
      reference = reference,
      cohort_info = cohort_info,
      kmer_length = kmer_length,

      pb_conda_image = pb_conda_image,
      run_jellyfish = run_jellyfish
  }

  call fasta_agape.fasta_cohort as fasta_cohort {
    input:
      cohort_info = cohort_info,
      pb_conda_image = pb_conda_image
  }

  #run sample-level hifiasm -- call hifiasm/sample_hifiasm.cohort.wdl for all samples
  call sample_hifiasm.cohort.sample_hifiasm_cohort {
     input:
       fasta_info = fasta_cohort.fasta_info,
       reference = reference,
       pb_conda_image = pb_conda_image
  }

  #call sample/sample.agape.wdl for all samples defined in this family
  call sample.agape.sample_family {
    input:
      person_sample_names      = smrtcells_cohort.person_sample_names,
      person_sample            = smrtcells_cohort.person_bams,
      person_jellyfish_input   = smrtcells_cohort.person_jellyfish_count,

      regions = regions,
      reference = reference,

      ref_modimers = ref_modimers,
      person_movie_modimers = smrtcells_cohort.person_movie_modimers,

      tr_bed = tr_bed,
      chr_lengths = chr_lengths,

      pb_conda_image = pb_conda_image,
      deepvariant_image = deepvariant_image,

      run_jellyfish = run_jellyfish,

      tg_list = tg_list,
      tg_bed = tg_bed,
      score_matrix = score_matrix,
      last_reference = last_reference
  }
  
  call cohort.cohort {
    input:
      cohort_name = cohort_name,
      regions = regions,
      reference = reference,

      person_deepvariant_phased_vcf_gz = sample_family.person_deepvariant_phased_vcf_gz,

      chr_lengths = chr_lengths,

      hpoannotations = hpoannotations,
      hpoterms = hpoterms,
      hpodag = hpodag,
      gff = gff,
      ensembl_to_hgnc = ensembl_to_hgnc,
      js = js,
      lof_lookup = lof_lookup,
      clinvar_lookup = clinvar_lookup,
      gnomad_af = gnomad_af,
      hprc_af = hprc_af,
      allyaml = allyaml,
      ped = ped,

      person_svsigs = sample_family.person_svsig_gv,

      person_bams = smrtcells_cohort.person_bams,
      person_gvcfs = sample_family.person_gvcf,

      pb_conda_image = pb_conda_image,
      glnexus_image = glnexus_image
  }
 
  
  Int num_parents_list = length(parents_list)
  Boolean trio_yak = if num_parents_list == 2 then true else false

  #Run trio-level hifiasm -- call hifiasm/trio_hifiasm.cohort.wdl only if both parents exist
  if (trio_yak){
    call trio_hifiasm.cohort.trio_hifiasm_cohort {
      input:
       fasta_info = fasta_cohort.fasta_info,
       person_parents_names = fasta_cohort.person_parents_names,
       parents_list = parents_list,
       pb_conda_image = pb_conda_image,
       reference = reference,
       trioeval = trioeval,
       triobin = triobin
    }
  }
  
  output {
    Array[Array[IndexedData]] person_bams        = smrtcells_cohort.person_bams
    Array[Array[File?]] person_jellyfish_count    = smrtcells_cohort.person_jellyfish_count

    Array[IndexedData] person_gvcf                        = sample_family.person_gvcf
    Array[Array[Array[File]]] person_svsig_gv             = sample_family.person_svsig_gv
    Array[IndexedData] person_deepvariant_phased_vcf_gz   = sample_family.person_deepvariant_phased_vcf_gz

    Array[File?] person_tandem_genotypes           = sample_family.person_tandem_genotypes
    Array[File?] person_tandem_genotypes_absolute  = sample_family.person_tandem_genotypes_absolute
    Array[File?] person_tandem_genotypes_plot      = sample_family.person_tandem_genotypes_plot
    Array[File?] person_tandem_genotypes_dropouts  = sample_family.person_tandem_genotypes_dropouts

  }
}
