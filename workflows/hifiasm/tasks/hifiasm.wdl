version 1.0

import "../../common/structs.wdl"
import "gfa2asm.wdl" as gfa2asm

task hifiasm_assemble {
  input {
    Int threads = 48
    String sample_name
    String prefix = "~{sample_name}.asm"
    String log_name = "hifiasm.log"

    Array[File] movie_fasta
    String pb_conda_image
  }

  Float multiplier = 2
  Int disk_size = ceil(multiplier * size(movie_fasta, "GB")) + 20
#  Int disk_size = 200
  Int memory = threads * 3              #forces at least 3GB RAM/core, even if user overwrites threads

  command <<<
    echo requested disk_size =  ~{disk_size}
    echo
    source ~/.bashrc
    conda activate hifiasm
    echo "$(conda info)"

    (hifiasm -o ~{prefix} -t ~{threads} ~{sep=" " movie_fasta}) > ~{log_name} 2>&1
  >>>
  output {
    File hap1_p_ctg        = "~{prefix}.bp.hap1.p_ctg.gfa"
    File hap1_p_ctg_lowQ   = "~{prefix}.bp.hap1.p_ctg.lowQ.bed"
    File hap1_p_noseq      = "~{prefix}.bp.hap1.p_ctg.noseq.gfa"
    File hap2_p_ctg        = "~{prefix}.bp.hap2.p_ctg.gfa"
    File hap2_p_ctg_lowQ   = "~{prefix}.bp.hap2.p_ctg.lowQ.bed"
    File hap2_p_noseq      = "~{prefix}.bp.hap2.p_ctg.noseq.gfa"
    File p_ctg             = "~{prefix}.bp.p_ctg.gfa"
    File p_utg             = "~{prefix}.bp.p_utg.gfa"
    File r_utg             = "~{prefix}.bp.r_utg.gfa"
    File ec_bin            = "~{prefix}.ec.bin"
    File ovlp_rev_bin      = "~{prefix}.ovlp.reverse.bin"
    File ovlp_src_bin      = "~{prefix}.ovlp.source.bin"

    File log = "~{log_name}"
  }
  runtime {
    docker: "~{pb_conda_image}"
    preemptible: true
    maxRetries: 3
    memory: "~{memory}" + " GB"
    cpu: "~{threads}"
    disk: disk_size + " GB"
  }
}

task align_hifiasm {
  input {
    String sample_name
    String? reference_name

    String minimap2_args = "-L --secondary=no --eqx -ax asm5"
    Int minimap2_threads = 12
    Int samtools_threads = 3

    String log_name = "align_hifiasm.log"
    IndexedData target
    Array[File] query

    String asm_bam_name = "~{sample_name}.asm.~{reference_name}.bam"
    String pb_conda_image
    Int threads = 16
    String readgroup =  "@RG\\tID:~{sample_name}_hifiasm\\tSM:~{sample_name}"
    String samtools_mem = "8G"
  }

  Float multiplier = 3.25
  Int disk_size = ceil(multiplier * (size(target.datafile, "GB") + size(target.indexfile, "GB") + size(query, "GB"))) + 20

  command <<<
    echo requested disk_size =  ~{disk_size}
    echo
    source ~/.bashrc
    conda activate align_hifiasm
    echo "$(conda info)"

    (minimap2 -t ~{minimap2_threads} ~{minimap2_args} -R "~{readgroup}" ~{target.datafile} ~{sep=" " query} \
            | samtools sort -@ ~{samtools_threads} -T $PWD -m ~{samtools_mem} > ~{asm_bam_name} \
            && samtools index -@ ~{samtools_threads} ~{asm_bam_name}) > ~{log_name} 2>&1
  >>>
  output {
    File asm_bam = "~{asm_bam_name}"
    File asm_bai = "~{asm_bam_name}.bai"
    File log = "~{log_name}"
  }
  runtime {
    docker: "~{pb_conda_image}"
    preemptible: true
    maxRetries: 3
    memory: "256 GB"
    cpu: "~{threads}"
    disk: disk_size + " GB"
  }
}


workflow hifiasm {
  input {
    String sample_name

    Array[File] movie_fasta

    IndexedData target
    String? reference_name
    String pb_conda_image
  }

  call hifiasm_assemble {
    input:
      sample_name = sample_name,
      movie_fasta = movie_fasta,
      pb_conda_image = pb_conda_image
  }

  call gfa2asm.gfa2asm as gfa2asm {
    input:
      hap1_p_ctg_gfa = hifiasm_assemble.hap1_p_ctg,
      hap2_p_ctg_gfa = hifiasm_assemble.hap2_p_ctg,
      p_ctg_gfa = hifiasm_assemble.p_ctg,
      p_utg_gfa = hifiasm_assemble.p_utg,
      r_utg_gfa = hifiasm_assemble.r_utg,
      reference = target,
      pb_conda_image = pb_conda_image
  }

  call align_hifiasm {
    input:
      sample_name = sample_name,
      target = target,
      reference_name = reference_name,
      query = [
        gfa2asm.hap1_fasta_gz,
        gfa2asm.hap2_fasta_gz
      ],
      pb_conda_image = pb_conda_image
  }

  output {
  }
}

