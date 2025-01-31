version 1.0

import "common_bgzip_vcf.wdl" as bgzip_vcf
import "../../common/structs.wdl"


task pbsv_call {
  input {
    Int threads = 8
    Int memory_GB = 64
    String extra = "--ccs -m 20 -A 3 -O 3"
    String loglevel = "INFO"

    String log_name = "pbsv_call.log"

    Array[File] cohort_person_svsigs
    IndexedData reference
    String cohort_name

    String pbsv_vcf_name = "~{cohort_name}.~{reference.name}.pbsv.vcf"
    String pb_conda_image
  }

  Float multiplier = 3.25
  Int disk_size = ceil(multiplier * (size(reference.datafile, "GB") + size(reference.indexfile, "GB") + size(cohort_person_svsigs, "GB"))) + 20
#  Int disk_size = 200

  command <<<
    echo requested disk_size =  ~{disk_size}
    echo
    source ~/.bashrc
    conda activate pbsv
    echo "$(conda info)"

    datafile="$(basename -- $~{reference.datafile} )"

    ln -s ~{reference.datafile} $datafile.fasta

    (
      pbsv call ~{extra} \
        --log-level ~{loglevel} \
        --num-threads ~{threads} \
        $datafile.fasta ~{sep=" " cohort_person_svsigs}  ~{pbsv_vcf_name}
    ) > ~{log_name} 2>&1

  >>>
  output {
    File log = "~{log_name}"
    File pbsv_vcf = "~{pbsv_vcf_name}"
  }
  runtime {
    docker: "~{pb_conda_image}"
    preemptible: true
    maxRetries: 3
    memory: "~{memory_GB} GB"
    cpu: "~{threads}"
    disk: disk_size + " GB"
  }
}

workflow pbsv {
  input {
    Array[Array[Array[File]]] person_svsigs
    IndexedData reference
    String cohort_name
    String pb_conda_image
  }

  Array[File] flattened_person_svsigs =   flatten(flatten(person_svsigs))

  call pbsv_call {
    input:
      cohort_name = cohort_name,
      cohort_person_svsigs = flattened_person_svsigs,
      reference = reference,
      pb_conda_image = pb_conda_image
    }

  call bgzip_vcf.bgzip_vcf {
      input :
        vcf_input = pbsv_call.pbsv_vcf,
        pb_conda_image = pb_conda_image
    }

  output {
    IndexedData pbsv_vcf = bgzip_vcf.vcf_gz_output
  }
}
