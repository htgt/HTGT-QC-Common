
use strict;
use warnings;



use ExtUtils::MakeMaker 6.30;



my %WriteMakefileArgs = (
  "ABSTRACT" => "Common QC Code",
  "AUTHOR" => "Wellcome Trust Sanger Institute",
  "BUILD_REQUIRES" => {
    "Bio::Seq" => 0,
    "English" => 0,
    "File::Compare" => 0,
    "File::Find" => 0,
    "File::Temp" => 0,
    "FindBin" => 0,
    "HTGT::DBFactory" => 0,
    "Test::More" => "0.88",
    "Test::Most" => 0
  },
  "CONFIGURE_REQUIRES" => {
    "ExtUtils::MakeMaker" => "6.30"
  },
  "DISTNAME" => "HTGT-QC-Common",
  "EXE_FILES" => [
    "bin/crispr_allele_damage.pl",
    "bin/fetch-seq-reads.sh",
    "bin/crispr_damage_analysis.pl",
    "bin/merge_vcf_variants.pl"
  ],
  "LICENSE" => "perl",
  "NAME" => "HTGT::QC::Common",
  "PREREQ_PM" => {
    "Array::Compare" => 0,
    "Bio::EnsEMBL::Variation::Utils::BaseVepPlugin" => 0,
    "Bio::SeqIO" => 0,
    "Config::Scoped" => 0,
    "Const::Fast" => 0,
    "Data::Dump" => 0,
    "Data::Dumper" => 0,
    "Data::UUID" => 0,
    "DesignCreate::Util::Exonerate" => 0,
    "Exporter" => 0,
    "File::Which" => 0,
    "Getopt::Long" => 0,
    "IO::Handle" => 0,
    "IPC::Run" => 0,
    "IPC::System::Simple" => 0,
    "Iterator::Simple" => 0,
    "List::MoreUtils" => 0,
    "List::Util" => 0,
    "Log::Log4perl" => 0,
    "Moose" => 0,
    "MooseX::ClassAttribute" => 0,
    "MooseX::Log::Log4perl" => 0,
    "MooseX::StrictConstructor" => 0,
    "MooseX::Types::Path::Class" => 0,
    "MooseX::Types::Path::Class::MoreCoercions" => 0,
    "Parse::BooleanLogic" => 0,
    "Path::Class" => 0,
    "Pod::Usage" => 0,
    "Scalar::Util" => 0,
    "Sub::Exporter" => 0,
    "Throwable::Error" => 0,
    "Try::Tiny" => 0,
    "YAML::Any" => 0,
    "base" => 0,
    "feature" => 0,
    "namespace::autoclean" => 0,
    "strict" => 0,
    "warnings" => 0
  },
  "VERSION" => "0.025",
  "test" => {
    "TESTS" => "t/*.t"
  }
);


unless ( eval { ExtUtils::MakeMaker->VERSION(6.56) } ) {
  my $br = delete $WriteMakefileArgs{BUILD_REQUIRES};
  my $pp = $WriteMakefileArgs{PREREQ_PM};
  for my $mod ( keys %$br ) {
    if ( exists $pp->{$mod} ) {
      $pp->{$mod} = $br->{$mod} if $br->{$mod} > $pp->{$mod};
    }
    else {
      $pp->{$mod} = $br->{$mod};
    }
  }
}

delete $WriteMakefileArgs{CONFIGURE_REQUIRES}
  unless eval { ExtUtils::MakeMaker->VERSION(6.52) };

WriteMakefile(%WriteMakefileArgs);



