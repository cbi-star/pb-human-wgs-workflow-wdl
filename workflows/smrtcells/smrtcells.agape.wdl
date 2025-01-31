version 1.0

# A simplified data structure, Array[SampleInfo], is used here, and unffacted/affected lines are all removed by Charlie Bi
# Whenever affected/unaffected appears, it is removed and rewritten with one line of new code

import "smrtcells.person.wdl" as smrtcells_person
import "../common/structs.wdl"


workflow smrtcells_cohort {
  input {
    IndexedData reference
    Array[SampleInfo] cohort_info
    Int kmer_length

    String pb_conda_image
    Boolean run_jellyfish
  }

  scatter (sample in cohort_info) {
    call smrtcells_person.smrtcells_person as smrtcells_person {
      input:
        reference = reference,
        sample = sample,
        kmer_length = kmer_length,

        pb_conda_image = pb_conda_image,
        run_jellyfish = run_jellyfish
    }
  }

  output {
    Array[Array[IndexedData]] person_bams         = if defined(smrtcells_person.bams)             then smrtcells_person.bams              else []
    Array[Array[File?]] person_jellyfish_count     = if defined(smrtcells_person.jellyfish_count)  then smrtcells_person.jellyfish_count   else []
    Array[String] person_sample_names            = if defined(smrtcells_person.sample_names)     then smrtcells_person.sample_names      else []
    Array[Array[String]] person_parents_names            = if defined(smrtcells_person.parents_names)     then smrtcells_person.parents_names      else []
    Array[Array[File?]] person_movie_modimers     = if defined(smrtcells_person.movie_modimers)  then smrtcells_person.movie_modimers   else []
  }
}
