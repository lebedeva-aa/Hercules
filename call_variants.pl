#!/usr/bin/env perl

use strict;
use warnings;
use Dir::Self;
use lib __DIR__ . '/lib';
use Sample;
use Design;
use Data::Dumper;
use threads;
use Storable qw ( freeze thaw );
use List::Util qw(min);
use List::MoreUtils qw(uniq);
use Thread::Queue;

my $current_dir = __DIR__;
my $test_folder = "$current_dir/test";
my $log_file = "$test_folder/log";
my $n_threads = 13;
my $list_control = $ARGV[0]; # bamListHRDRef
#my $sample_bam = $ARGV[1]; # /home/onco-admin/RnD/UEBAcall/5099.bam
my $input_panel = $ARGV[1]; # /home/onco-admin/ATLAS_software/aod-pipe/panel_info/AODHRD15/AODHRD15.designed.bed
my $input_vcf = $ARGV[2]; # test.vcf
my $panel_size = $ARGV[3];
$panel_size = 1 unless defined $panel_size;

open (my $log_fh, ">$log_file");

my $qscore_averaging_range      = 1; # Phred quality score is average in this window/ This value defines half of the window length.
my $minimum_coverage = 2; # Positions with coverage lower this value will be ignored (defined as non-detectable)

my $work_PPB  = Thread::Queue->new;

sub generate_seed {
        my @set = ('0' ..'9', 'A' .. 'Z', 'a' .. 'z');
        my $str = join '' => map $set[rand @set], 1 .. 15;
        return $str
        }

sub worker_PPB {
	while ( my $passed = $work_PPB->dequeue ) {
		my $seed	= $passed->[0];
		my $counter	= $passed->[1];
		print $log_fh "Started PPB $seed $counter\n";
		my $cmd = `R --slave -f $current_dir/lib/ppb.r --args $test_folder/ppb_$seed.in.$counter $test_folder/ppb_$seed.out.total.p$counter $test_folder/ppb_$seed.out.detailed.p$counter 2> $test_folder/ppb_$seed.log.p$counter`;
		`$cmd`;
		}
	}

my $pval_calc_seed = generate_seed();

my %group_seeds;
my $group_seed_count = 0;
my $group_seed_counter = 1;
open (my $pval_calc_fh, ">$test_folder/ppb_$pval_calc_seed.in.$group_seed_counter");
threads->create( \&worker_PPB ) for 1 .. $n_threads;

foreach my $sample (keys %{$sample_data}) {
	foreach my $index (uniq(map {$_ = substr($_, 0, index($_, '@'))} keys %job_list)) {
		my $pval = [];
		my $ad = [];
		my $dp = [];
		my $seed = generate_seed();
		$group_seeds{$seed} = {'index' => $index, 'sample' => $sample};
		foreach my $job_element (grep(/$index/, (keys %job_list))) {
			my $altCnt;
			my $depth;
			unless (defined $sample_data->{$sample}->{$job_element}) {
				$altCnt = "NA";
				$depth = "NA";
				} else {
				$altCnt = $sample_data->{$sample}->{$job_element}->{altCnt};
				$depth  = $sample_data->{$sample}->{$job_element}->{depth};
				}
			my $alpha_val  = $beta{$job_element}->{alpha};
			my $beta_val   = $beta{$job_element}->{beta};
			my $mean_val   = $beta{$job_element}->{mean};
			#my $cmd = "R --slave -f $current_dir/lib/ppb.r --args $altCnt $depth $alpha_val $beta_val $mean_val $panel_size";
			print $pval_calc_fh "$seed\t$altCnt\t$depth\t$alpha_val\t$beta_val\t$mean_val\t1\n";
			print $log_fh "$index\t$sample\t$seed\t$altCnt\t$depth\t$alpha_val\t$beta_val\t$mean_val\t1\n";
			++$group_seed_count;
			}
		if ($group_seed_count > 3000) {
			close $pval_calc_fh;
			$work_PPB->enqueue( [$pval_calc_seed, $group_seed_counter] );
			$group_seed_count = 0;
			$group_seed_counter += 1;
			open ($pval_calc_fh, ">$test_folder/ppb_$pval_calc_seed.in.$group_seed_counter");

			}
		}
	}
close $pval_calc_fh;
if ($group_seed_count > 0) {
	$work_PPB->enqueue( [$pval_calc_seed, $group_seed_counter] );
	}

$work_PPB->end;
$_->join for threads->list;

`cat $test_folder/ppb_$pval_calc_seed.out.total.p* > $test_folder/ppb_$pval_calc_seed.out.total`;
`cat $test_folder/ppb_$pval_calc_seed.out.detailed.p* > $test_folder/ppb_$pval_calc_seed.out.detailed`;

my @pval_by_group;
open (PVALBYGROUP, "<$test_folder/ppb_$pval_calc_seed.out.detailed");

while (<PVALBYGROUP>) {
	chomp;
	my @mas = split/\t/;
	my $pval = $mas[3];
	$pval = ((-1)*int(10*log($pval)/log(10))/1) unless $pval eq 'NA';
	my $ad = $mas[1];
	$ad = int($ad) unless $ad eq 'NA';
	my $alpha = $mas[4];
	my $beta = $mas[5];
	$alpha = int(1000*$alpha)/1000 unless $alpha eq 'NA';
	$beta = int(1000*$beta)/1000 unless $beta eq 'NA';
	push @pval_by_group, {'seed' => $mas[0], "AD" => $ad, "DP" => $mas[2], "P" => $pval, "A" => $alpha, "B" => $beta};
	}

close PVALBYGROUP;

open (PVALTOTAL, "<$test_folder/ppb_$pval_calc_seed.out.total");

while (<PVALTOTAL>) {
	chomp;
	my @mas = split/\t/;
	my $pval = $mas[1];
	$pval = ((-1) * int(10*log(min(1, ($pval * $panel_size)))/log(10))/1) unless $pval eq 'NA';
	my $i = 0;
	my $index  = $group_seeds{$mas[0]}->{index};
	my $sample = $group_seeds{$mas[0]}->{sample};
	print "$sample\t$index\t$pval\t",join(';', map {++$i; "AODAD$i=".$_->{AD}.",".$_->{DP}.";AODP$i=".$_->{P}.";AODA$i=".$_->{A}.";AODB$i=".$_->{B}} (grep {$_->{seed} eq $mas[0]} @pval_by_group)),"\n";
        }

close PVALTOTAL;




__END__

=head1 NAME

CREATE DISTRIBUTION PARAMETERS

=head1 SYNOPSIS

CREATE DISTRIBUTION PARAMETERS

Options:

    -bdata  [REQUIRED] - list of input bam files (either first or second collumn is path to .bam file)
    -v  [REQUIRED] - list of target variants in .vcf format
    -p  [REQUIRED] - path to bed file (amplicon panel)
    -n  [OPTIONAL] - number of threads to be used
    -bdata  [REQUIRED] - input/output file with site-specific distribution parameters
    -mode  [OPTIONAL] - CREATE/APPEND[DEFAULT]. Create will overwrite existing data in .bdata output file. Append will only append new sites from input .vcf file into output file








































