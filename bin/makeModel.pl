#!/usr/bin/perl
#SBATCH -t 72:00:00
#SBATCH --mem=10G
#SBATCH -J makeModel.pl

use Math::Trig;
use Getopt::Long qw(GetOptions);

$ENV{'PATH'}="/nfs/amino-home/zhanglabs/bin:$ENV{'PATH'}";

$user="$ENV{USER}"; # user name, please change it to your own name, i.e. 'jsmith'
$outdir="";
$njobmax=1; #maximum number of jobs submitted by you
$Q="batch"; #what queue you want to use to submit your jobs
$oj="1"; #flag number for different runs, useful when you run multiple jobs for same protein
#$svmseq="no";  # run I-TASSER
######### Needed changes ended #################################

my $s="";
my $bindir="/nfs/amino-home/ewbell/PEPPI/bin/C-I-TASSER";
my $benchflag=0;
my $domaindiv=0;

GetOptions(
    "benchmark" => \$benchflag,
    "domains" => \$domaindiv,
    "outdir=s" => \$outdir,
    "target=s" => \$s
    ) or die "Invalid arguments were passed into C-I-TASSER";

my $run=($benchflag) ? "benchmark" : "real";

eval{
    local $SIG{ALRM}=sub{ die "alarm\n"};
    alarm(259000);
    CITASSER();
    #alarm(0);
};

if ($@){
    die unless $@ eq "alarm\n";
    print "Max time achieved, resubmitting...\n";
    my $fname=__FILE__;
    my $args="-o $outdir -t $target";
    $args="$args -b" if ($benchflag);
    $args="$args -d" if ($domaindiv);
    print `sbatch $fname $args`;
}

exit();

sub CITASSER{
    #################################################################
    # Disclaimer: C-I-TASSER is the software developed at Zhang Lab #
    # at DCMB, University of Michigan. No any part of this package  #
    # could be released outside the Zhang Lab without permission    #
    # from the orginal authors. Violation of this rule may result   #
    # in lawful consequences.                                       #
    #################################################################

    ######## What this program does? ###############################
    #
    # This program generates most input files for C-I-TASSER.
    #   input files:
    #	seq.fasta  	(query sequence in FASTA format)
    #   output files:
    #	seq.seq  	(query sequence in FASTA format)
    #	seq.dat		(predicted secondary structure)
    #	seq.ss		(predicted secondary structure)
    #	rmsinp		(length file)
    #	exp.dat		(predicted solvant assessibility)
    #	pair3.dat	(general pair-wise contact potential)
    #	pair1.dat	(general pair-wise contact potential)
    #       init.XXX        (threading templates from XXX, eg, XXX=hhpred)
    #       XXX.dat         (contact  prediction from XXX, eg, XXX=respre)
    #
    #  Tips: All the intermediate files are deposited at 
    #       /nfs/amino-home/zhng/C-I-TASSER/version_2013_03_20/test/record
    #       When you find some of the input files fail to generate, you can rerun 
    #       the specific jobs rather the entire mkinput.pl, e.g. if 'init.BBB' 
    #       is not generated, you can just rerun 
    #       /nfs/amino-home/zhng/C-I-TASSER/version_2013_03_20/test/record/BBB15_2rjiA
    #       
    ################################################################


    ######## ALL these variables MUST be changed before run ###############
    #$outdir="$outdir/fasta";

    ### Please do not change files below unless you know what you are doing #####
    #
    # step-0: prepare 'seq.txt' from 'seq.fasta' (local)
    # Step-1: make 'seq.dat', 'rmsinp' by runpsipred.pl (qsub)
    # Step-2: make 'exp.dat'   (qsub)
    # Step-3: make 'pair3.dat' and 'pair1.dat' (qsub)
    # step-4: run threading.pl (qsub)
    # step-5: run contact.pl   (qsub)
    #
    # The log files are in $outdir/record if you want to debug your files

    $lib="/nfs/amino-library";

    ################# directory assignment #############################
    $u=substr($user,0,1);
    $librarydir="$lib"; #principle library, should not be changed
    $recorddir="$outdir/record"; #for record all log files and intermiddiate job files
    `mkdir -p $recorddir`;

    @TT=qw(
	HHW

	SPX
	FF3
	MUS
	RAP3
	HHP

	JJJb
	IIIe
	VVV
	BBB
	WWW

	RRR3
	PRC
	); #threading programs
    # when you update @TT, please remember to update type.pl

    #HHW-HHpred (modified)
    #SPX-Sparkx
    #FF3-FFAS3D
    #RAP3-Raptor
    #HHP-HHpred (modified)

    #MUS-MUSTER
    #JJJb-PPI (unpublished)
    #IIIe-HHpred_local
    #VVV--SP3
    #RRR3-FFAS

    #WWW--PPI (unpublished)
    #BBB--PROSPECT2
    #PRC--PRC

    #------following programs does not need seq.dat:
    #SPX
    #HHP
    #IIIe 
    #IIIj
    #UUU
    #VVV
    #CCC
    #RAP3
    #RRR3
    #pgen
    #PRC
    #------following need seq.dat but will generate on their own:
    #WWW   need blast but generate by itself
    #MUS   need blast and seq.dat but generate by itself
    #JJJb  need seq.dat.ss (generated by its own)
    #------following will wait for the master program to generate seq.dat:
    #BBB   need seq.dat.ss (waiting)
    #GGGd  need seq.dat (waiting)
    #NNNd  need seq.dat (waiting)
    #RRR6  need seq.dat (waiting)
    #HHWmod  need seq.dat (waiting)

    #### parameters #########////
    if($run eq "benchmark"){
	$id_cut=0.3;   #cut-off  of sequence idendity
    }else{
	$id_cut=10;   #cut-off  of sequence idendity
    }
    $n_temp=20;     #number of templates
    $o=""; #will generate init$o.MUS

    $qzy=`$bindir/qzy`; #script for statistics of all jobs


    $datadir="$outdir/$s";
    $datadir1="$outdir";
    if(!-s "$datadir/seq.fasta"){
	printf "error: without $datadir/seq.fasta\n";
	goto pos1;
    }

    ############ step-0: convert 'seq.fasta' to 'seq.txt' with standard format ####
    open(seqtxt,"$datadir/seq.fasta");
    $sequence="";
    while($line=<seqtxt>){
	goto pos1 if($line=~/^>/);
	if($line=~/(\S+)/){
	    $sequence .=$1;
	}
      pos1:;
    }
    close(seqtxt);
    open(fasta,">$datadir/seq.txt");
    printf fasta "> $s\n";
    $Lch=length $sequence;
    for($i=1;$i<=$Lch;$i++){
	$seq1=substr($sequence,$i-1,1);
	$seq{$i}=$ts{$seq1};
	printf fasta "$seq1";
	if(int($i/60)*60==$i){
	    printf fasta "\n";
	}
    }
    printf fasta "\n";
    close(fasta);
=pod
	### check number of my submitted jobs to decide whether I can submit new jobs ##
      pos50:;
    $jobs=`$bindir/jobcounter.pl $user`;
    if($jobs=~/njobuser=\s+(\d+)\s+njoball=\s+(\d+)/){
	$njobuser=$1;
	$njoball=$2;
    }
    if($njobuser+scalar(@TT) > $njobmax){
	printf "$njobuser > $njobmax, let's wait 2 minutes\n";
	sleep (120);
	goto pos50;
    }
=cut

	#@@@@@@@@@@@@@@@@ step-1: generate 'seq.dat' and seq.dat.ss' @@@@@@@@@@@@@@@@@@@@@@
	$tmp1="$datadir/seq.dat";
    $tmp2="$datadir/rmsinp";
    if(-s "$tmp1" >50 && -s "$tmp2" >5){
	open(tmp,"$tmp1");
	$line=<tmp>;
	close(tmp);
	if($line=~/\d+/){
	    open(tmp,"$tmp2");
	    $line=<tmp>;
	    close(tmp);
	    if($line=~/(\d+)/){
		goto pos1a; #files are done
	    }
	}
    }
    $mod=`cat $bindir/mkseqmod`;
    ###
    $tag="mkseq$o$u$oj\_$s"; # unique name
    $jobname="$recorddir/$tag";
    $errfile="$recorddir/err_$tag";
    $outfile="$recorddir/out_$tag";
    $walltime="walltime=10:00:00,mem=3000mb";
    ###
    $mod1=$mod;
    $mod1=~s/\!ERRFILE\!/$errfile/mg;
    $mod1=~s/\!OUTFILE\!/$outfile/mg;
    $mod1=~s/\!WALLTIME\!/$walltime/mg;
    $mod1=~s/\!NODE\!/$node/mg;
    $mod1=~s/\!TAG\!/$tag/mg;
    $mod1=~s/\!USER\!/$user/mg;
    $mod1=~s/\!DATADIR\!/$datadir/mg;
    $mod1=~s/\!LIBRARYDIR\!/$librarydir/mg;
    open(job,">$jobname");
    print job "$mod1\n";
    close(job);
    `chmod a+x $jobname`;

    ######### check whether the job is running ##########

=pod
	if($jobname=~/record\/(\S+)/){
	    $jobname1=$1;
	    if($qzy=~/$jobname1/){
		printf "$jobname1 is running, neglect the job\n";
		goto pos1a;
	    }
    }


    ########## submit my job ##############
  pos41:;
    $bsub=`qsub -q $Q $jobname`;
    chomp($bsub);
    if(length $bsub ==0){
	sleep(20);
	goto pos41;
    }
    $date=`/bin/date`;
    chomp($date);
    open(note,">>$recorddir/note.txt");
    print note "$jobname\t at $date $bsub\n";
    close(note);
    printf "$jobname was submitted.\n";
  pos1a:;
=cut

	print `$jobname`;
  pos1a:;

    #@@@@@@@@@@@@@@@@ step-3: generate 'pair3.dat' and 'pair1.dat' @@@@@@@@@@@@@@@@@@@@@@
    $tmp1="$datadir/pair1.dat";
    $tmp2="$datadir/pair3.dat";
    if(-s "$tmp1" >50 && -s "$tmp2" >5){
	open(tmp,"$tmp1");
	$line=<tmp>;
	close(tmp);
	if($line=~/\d+\s+\S+/){
	    open(tmp,"$tmp2");
	    $line=<tmp>;
	    close(tmp);
	    if($line=~/(\d+)\s+\S+/){
		goto pos1c; #files are done
	    }
	}
    }
    $mod=`cat $bindir/mkpairmod99`;
    ###
    $tag="mkp$o$u$oj\_$s"; # unique name
    $jobname="$recorddir/$tag";
    $errfile="$recorddir/err_$tag";
    $outfile="$recorddir/out_$tag";
    $walltime="walltime=30:00:00,mem=3000mb";
    ###
    $mod1=$mod;
    $mod1=~s/\!TAG\!/$tag/mg;
    $mod1=~s/\!USER\!/$user/mg;
    $mod1=~s/\!S\!/$s/mg;
    $mod1=~s/\!INPUTDIR\!/$datadir/mg;
    $mod1=~s/\!RUN\!/$run/mg;
    $mod1=~s/\!BINDIR\!/$bindir/mg;
    open(job,">$jobname");
    print job "$mod1\n";
    close(job);
    `chmod a+x $jobname`;
=pod
	######### check whether the job is running ##########
	if($jobname=~/record\/(\S+)/){
	    $jobname1=$1;
	    if($qzy=~/$jobname1/){
		printf "$jobname1 is running, neglect the job\n";
		goto pos1c;
	    }
    }

  pos43:;
    $bsub=`qsub -q $Q -e $errfile -o $outfile -l $walltime $jobname`;
    chomp($bsub);
    if(length $bsub ==0){
	sleep(20);
	goto pos43;
    }
    $date=`/bin/date`;
    chomp($date);
    open(note,">>$recorddir/note.txt");
    print note "$jobname\t at $date $bsub\n";
    close(note);
    printf "$jobname was submitted.\n";
  pos1c:;
=cut

	print `$jobname`;
  pos1c:;

    #@@@@@@@@@@@@@@@@ step-4: run LOMETS threading @@@@@@@@@@@@@@@@@@@@@@

    #### dirs ###############
    $workdir=$datadir;
    $data_dir=$datadir;
    $lib_dir=$librarydir; 

    ##### circle:
    foreach $T(@TT){
	$tmp="$datadir/init.$T";
	if(!-s "$tmp"){
	    $tag="$o$u$T$oj\_$s"; # unique name
	    $jobmod="$T"."mod";
	    if($T eq "RRR6" || $T=~/RAP/ || $T=~/HHW/ || $T=~/CET/ || $T=~/MAP/){ # need multiple nodes or high memory
		$walltime="walltime=40:00:00,mem=15000mb"; #<>=2.5h; [1.5,5.8]
		if($Lch>1000){
		    $walltime="walltime=40:00:00,mem=25000mb"; #<>=2.5h; [1.5,5.8]
		}
	    }else{
		$walltime="walltime=40:00:00,mem=4000mb";
		if($Lch>1000){
		    $walltime="walltime=40:00:00,mem=10000mb"; #<>=2.5h; [1.5,5.8]
		}
	    }
	    &submitjob($workdir,$recorddir,$lib_dir,$data_dir,$bindir,
		       $tag,$jobmod,$walltime,$id_cut,$n_temp,
		       $s,$o,$Q,$user,$run,$outdir);
	}
    }

    #####//////////////
    sub submitjob{
	my($workdir,$recorddir,$lib_dir,$data_dir,$bindir,
	   $tag,$jobmod,$walltime,$id_cut,$n_temp,
	   $s,$o,$Q,$user,$run,$outdir)=@_;

	###
	$jobname="$recorddir/$tag";
	$runjobname="$recorddir/$tag\_run";
	$errfile="$recorddir/err_$tag";
	$outfile="$recorddir/out_$tag";
	$node="nodes=1:ppn=1";
	###
	#------- runjobname ------>
	$mod=`cat $bindir/runjobmod`;
	$mod=~s/\!ERRFILE\!/$errfile/mg;
	$mod=~s/\!OUTFILE\!/$outfile/mg;
	$mod=~s/\!WALLTIME\!/$walltime/mg;
	$mod=~s/\!RECORDDIR\!/$recorddir/mg;
	$mod=~s/\!JOBNAME\!/$jobname/mg;
	$mod=~s/\!NODE\!/$node/mg;
	$mod=~s/\!TAG\!/$tag/mg;
	open(runjob,">$runjobname");
	print runjob "$mod\n";
	close(runjob);
	`chmod a+x $runjobname`;
	###
	#------- jobname ------>
	$mod=`cat $bindir/$jobmod`;
	$mod=~s/\!S\!/$s/mg;
	$mod=~s/\!O\!/$o/mg;
	$mod=~s/\!ID_CUT\!/$id_cut/mg;
	$mod=~s/\!N_TEMP\!/$n_temp/mg;
	$mod=~s/\!DATA_DIR\!/$outdir/mg;
	$mod=~s/\!DATADIR\!/$outdir/mg;
	$mod=~s/\!LIB_DIR\!/$lib_dir/mg;
	$mod=~s/\!TAG\!/$tag/mg;
	$mod=~s/\!USER\!/$user/mg;
	$mod=~s/\!RUN\!/$run/mg;
	open(job,">$jobname");
	print job "$mod\n";
	close(job);
	`chmod a+x $jobname`;
=pod
	    ######### check whether the job is running ##########
	    if($jobname=~/record\/(\S+)/){
		$jobname1=$1;
		if($qzy=~/$jobname1/){
		    printf "$jobname1 is running, neglect the job\n";
		    goto pos1d;
		}
	}

	#-------job submision --------------->
      pos44:;
	$bsub=`qsub -q $Q $runjobname`;
	chomp($bsub);
	if(length $bsub ==0){
	    sleep(20);
	    goto pos44;
	}
	$date=`/bin/date`;
	chomp($date);
	open(note,">>$recorddir/note.txt");
	print note "$jobname\t at $date $bsub\n";
	close(note);
	print "$jobname was submitted.\n";
=cut
	    print `$jobname`;
      pos1d:;
    }

  pos1:;

    #
    #
    #  START MKINPUT2.pl
    #
    #


    ### Please do not change files below unless you know what you are doing #####
    $home="/nfs/amino-home/zhng";
    $home = "/home/yzhang" if(!-d "$home");
    $lib="/nfs/amino-library";
    $lib="/library/yzhang" if(!-d "$lib");

    @TT=qw(
	HHW

	SPX
	FF3
	MUS
	RAP3
	HHP

	JJJb
	IIIe
	VVV
	BBB
	WWW

	RRR3
	PRC
	); #threading programs

    $librarydir="$lib";
    $initall="init.dat"; #LOMETS
    $Me=15;
    $Mh=17;
    $t=""; #input: init$t.MUS
    $o=""; #output: comb$o.dat

    #--- following parameters are useless; they are here because of historical reasons:
    $rostype="NOT"; #ROS or NOT
    $quatype="NOT"; #QUA, RQ2, or NOT
    $sort="no";
    $n_ita_sort=0; #ITA is never used for sort, useless
    $n_ros_sort=2;
    $n_qua_sort=5;
    ########### for chunk--------->
    $usechunk="no"; #yes, for additional comb.dat
    $m_top=12; #top 10 models at each chunk position for comb.dat
    $mag=1; #no use
    $n_int_CHU=8;
    $M0_CHU=1; #number of chunk_template used to extract distL.dat
    ########### for ROS--------->
    $useros="no"; #yes, for additional comb.dat
    $m_top2=0; #number of templates for additional comb.dat
    $mag2=1; #no use
    $n_int_CHU2=8; #interval for distL
    $M0_CHU2=1;
    $n_ros=9; #total number of QUA/ROS for comb.dat in init.dat
    ########### for chunk_T, i.e. SEGMER --------->
    $usechunkT="no"; #yes, for additional comb.dat
    $m_top3=6; #top 10 models at each chunk_T position
    $mag3=1; #no use
    $n_int_CHU3=8; #inteval for distL
    $M0_CHU3=1; #first distL prediction
    $Z_cut=0;
    #^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

    $mod=`cat $bindir/mkresmod`;
    $recorddir="$outdir/record";
    `/bin/mkdir -p $recorddir`;

    $datadir="$outdir/$s";
    open(rmsinp,"$datadir/rmsinp");
    <rmsinp>=~/\d+\s+(\d+)/;
    $Lch=$1;
    close(rmsinp);
    foreach $init(@TT){
	if($Lch>200 && $init eq "RAP"){
	    goto pos2a;
	}
	if(!-s "$datadir/init.$init"){
	    printf "\n$datadir/init.$init has not yet generated.\n";
	    printf "Please wait till the files are generated or check whether mkinput.pl was run correctly.\n";
	    printf "Your restraint files for $s have not been generated.\n\n";
	    #exit();
	    #goto pos_end;
	}
      pos2a:;
    }

    ############## decide target type ------------>
    $rst=`$bindir/type.pl $datadir`;
    if($rst=~/The final type=\s+(\S+)/){
	$type=$1; # triv/easy/hard/very
    }
    if($type!~/\S/){
	print "warning: type.pl is not correct, let's set target as hard.\n";
	$type="hard";
    }
    print "target type = $type\n";
    open(a,">$datadir/type.txt");
    print a "$rst\n";
    close(a);
    #^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

    #printf "$s\n";
    ###
    $tag="mkres$o\_$oj\_$s"; # unique name
    $jobname="$recorddir/$tag";
    $errfile="$recorddir/err_$tag";
    $outfile="$recorddir/out_$tag";
    $walltime="walltime=0:20:00,mem=2000mb";
    ###
    $mod1=$mod;
    $mod1=~s/\!ERRFILE\!/$errfile/mg;
    $mod1=~s/\!OUTFILE\!/$outfile/mg;
    $mod1=~s/\!WALLTIME\!/$walltime/mg;
    $mod1=~s/\!TAG\!/$tag/mg;

    $mod1=~s/\!O\!/$o/mg;
    $mod1=~s/\!S\!/$s/mg;
    $mod1=~s/\!OROS\!/$oros/mg;
    $mod1=~s/\!DATADIR\!/$datadir/mg;
    $mod1=~s/\!LIBRARYDIR\!/$librarydir/mg;
    $mod1=~s/\!INITALL\!/$initall/mg;
    $mod1=~s/\!INIT1\!/$init1/mg;
    $mod1=~s/\!INIT2\!/$init2/mg;
    $mod1=~s/\!INIT3\!/$init3/mg;
    $mod1=~s/\!MAG\!/$mag/mg;

    $mod1=~s/\!NINTCHU\!/$n_int_CHU/mg;
    $mod1=~s/\!M0CHU\!/$M0_CHU/mg;
    $mod1=~s/\!MTOP\!/$m_top/mg;
    $mod1=~s/\!MAG2\!/$mag2/mg;
    $mod1=~s/\!NINTCHU2\!/$n_int_CHU2/mg;
    $mod1=~s/\!M0CHU2\!/$M0_CHU2/mg;
    $mod1=~s/\!MTOP2\!/$m_top2/mg;
    $mod1=~s/\!NROS\!/$n_ros/mg;
    $mod1=~s/\!MTOP3\!/$m_top3/mg;
    $mod1=~s/\!MAG3\!/$mag3/mg;

    $mod1=~s/\!NINTCHU3\!/$n_int_CHU3/mg;
    $mod1=~s/\!M0CHU3\!/$M0_CHU3/mg;
    $mod1=~s/\!ZCUT\!/$Z_cut/mg;
    $mod1=~s/\!USEROS\!/$useros/mg;
    $mod1=~s/\!USER\!/$user/mg;
    $mod1=~s/\!USECHUNK\!/$usechunk/mg;
    $mod1=~s/\!USECHUNKT\!/$usechunkT/mg;

    $mod1=~s/\!ROSTYPE\!/$rostype/mg;
    $mod1=~s/\!QUATYPE\!/$quatype/mg;

    $mod1=~s/\!SORT\!/$sort/mg;
    $mod1=~s/\!NROSSORT\!/$n_ros_sort/mg;
    $mod1=~s/\!NQUASORT\!/$n_qua_sort/mg;
    $mod1=~s/\!NITASORT\!/$n_ita_sort/mg;

    $mod1=~s/\!Me\!/$Me/mg;
    $mod1=~s/\!Mh\!/$Mh/mg;
    $mod1=~s/\!T\!/$t/mg;

    $mod1=~s/\!BINDIR\!/$bindir/mg;

    open(job,">$jobname");
    print job "$mod1\n";
    close(job);
    `chmod a+x $jobname`;
    #printf "$jobname\n";

    ###################
    system("$jobname");

  pos_end:;

    #@@@@@@@@@@@@@@@@ step-5: generate contact.dat @@@@@@@@@@@@@@@@@@@@@@

    $modfile="$bindir/CONTACTmod";
    # this script will first generate MSA, and then initiate 'mk_contact.pl'
    # to submit contact prediction jobs automatically after MSA is created.

    $jobmod=`cat $modfile`;
    $tag="MSA$o$u$oj\_$s"; # unique name

    ######## prepare job file -------->
    $jobname="$recorddir/$tag";
    $errfile="$recorddir/err_$tag";
    $outfile="$recorddir/out_$tag";
    $walltime="walltime=10:00:00,mem=8000mb"; #need more space for nr, for multiple ncpu
    if($Lch>800){
	$walltime="walltime=10:00:00,mem=20000mb"; #need more space for nr
    }
    $node="nodes=1:ppn=1";
    ###
    #------- jobname ------>
    $mod=$jobmod;
    $mod=~s/\!ERRFILE\!/$errfile/mg;
    $mod=~s/\!OUTFILE\!/$outfile/mg;
    $mod=~s/\!RECORDDIR\!/$recorddir/mg;
    $mod=~s/\!WALLTIME\!/$walltime/mg;
    $mod=~s/\!BINDIR\!/$bindir/mg;
    $mod=~s/\!NODE\!/$node/mg;
    $mod=~s/\!USER\!/$user/mg;
    $mod=~s/\!O\!/$o/mg;
    $mod=~s/\!Q\!/$Q/mg;
    ##
    $mod=~s/\!TAG\!/$tag/mg;
    $mod=~s/\!S\!/$s/mg;
    $mod=~s/\!DATADIR1\!/$datadir1/mg;
    open(job,">$jobname");
    print job "$mod\n";
    close(job);
    `chmod a+x $jobname`;

    #printf "--------- $jobname\n";
    #system("$jobname");
    #exit();

    ########## skip the job if contact files are created ------>
    if(-s "$datadir/MSA/protein.aln" && -s "$datadir/nebconB.dat" && 
       -s "$datadir/gremlin.dat" && -s "$datadir/restriplet.dat" &&
       -s "$datadir/tripletres.dat" && -s "$datadir/metapsicov.dat" &&
       -s "$datadir/ccmpred.dat" && -s "$datadir/freecontact.dat"){
	printf "$datadir/contact map exist, neglect the job\n";
	goto pos1e;
    }
=pod
	######### check whether the job is running ##########
	if($jobname=~/record\/(\S+)/){
	    $jobname1=$1;
	    if($qzy=~/$jobname1/){
		printf "$jobname1 is running, neglect the job\n";
		goto pos1e;
	    }
    }

  pos42:;
    $bsub=`qsub -q $Q $jobname`;
    chomp($bsub);
    if(length $bsub ==0){
	sleep(20);
	goto pos42;
    }
    $date=`/bin/date`;
    chomp($date);
    open(note,">>$recorddir/note.txt");
    print note "$jobname\t at $date $bsub\n";
    close(note);
    print "$jobname was submitted.\n";

  pos1e:;
=cut

	print `$jobname`;
  pos1e:;

    #
    #
    # START SUBMITTASSER.pl
    #
    #


    $oj="1"; #flag number for different runs, useful when you run multiple jobs for same protein
    $svmseq="yes"; # run C-I-TASSER
    #$svmseq="no";  # run I-TASSER
    #####################################################////////













    ######## you do not need to change the content below ###########
    $lib="/nfs/amino-library";
    $lib="/library/yzhang" if(!-d "$lib");

    %ncycle=(
	'A'=>500,
	'M'=>250,
	'B'=>250,
	'F'=>250,
	);

    %switch=(
	'A'=>1, #ab
	'M'=>2, #rotation+translation
	'B'=>5, #rotation+translation+deformation, bug before
	'F'=>3, #freeze the template
	);

    @TT=qw(
	A
	M
	F
	);

    $nrun=1;
    ###### input files ###########
    $o="";
    $init="init$o.dat";
    $comb="comb$o.dat";
    $dist="dist$o.dat";
    $combCA="combCA$o.dat";
    $distL="distL$o.dat";
    $par="par$o.dat";
    $comb8CA="comb8CA$o.dat";
    $exp="exp.dat";
    $pair1="pair1.dat";
    $pair3="pair3.dat";

    $commondir="$lib/common"; #common files
    $hour=200; #$time=$hour_max if(Lch>220), 24*3=72, 24*4=96, 24*5=120

    ###
    $mod=`cat $bindir/submittassermod`;
    $recorddir="$outdir/record";
    `/bin/mkdir -p $recorddir`;

    ######### parameter for contact-map ------->
    $Wcon="combine";
    $fWcon="1";

    $qzy=`$bindir/qzy`;

    printf "--------- $s -------------\n";
    $datadir="$outdir/$s";

    ####### check input files ##############
    $checkinput=`$bindir/checkinput.pl $datadir $svmseq`;
    printf "$checkinput";
    if($checkinput=~/(\d+)\s+errors/){
	printf "You have errors in your input files. Please fix them before you run C-I-TASSER\n";
	printf "C-I-TASSER jobs for $s was not submitted\n";
	goto pos_end2;
    }

    ####### directories ###############//
    $outputdir=$datadir;

    ######## decide target type ###########
    open(a,"$datadir/type.txt");
    while($line=<a>){
	if($line=~/The final type=\s*(\S+)/){
	    $type=$1;
	}
    }
    close(a);
    if($type!~/\S/){
	print "warning: type.pl is not correct, let's set target as hard.\n";
	$type="hard";
    }
    open(rmsinp,"$datadir/rmsinp");
    <rmsinp>=~/\d+\s+(\d+)/;
    $Lch=$1;
    close(rmsinp);

    ######## decide number of runs ##################
    $i1{"A"}=1;
    $i1{"M"}=1;
    $i1{"F"}=1;
    if($type eq "triv" || $type eq "easy"){
	$n_temp=10;
    }else{
	$n_temp=20;
    }
    $i2{"A"}=5;
    $i2{"M"}=0;
    $i2{"F"}=0;
    if($Lch>250){
	$i2{"M"}=$n_temp;
    }
    if($Lch>400){
	$i2{"M"}=$n_temp;
	$i2{"F"}=$n_temp;
	$i2{"A"}=0; # added by chengxin: 'A' jobs is not scalable for big targets
    }

    foreach $T(@TT){
	for($i=$i1{$T};$i<=$i2{$T};$i++){
	    ###
	    $tag="$s\_$oj\_$i$T";
	    $jobname="$recorddir/$tag";
	    $errfile="$recorddir/err_$tag";
	    $outfile="$recorddir/out_$tag";
	    $walltime="walltime=$hour:59:00,mem=3000mb";
	    ###
	    $mod1=$mod;
	    $mod1=~s/\!ERRFILE\!/$errfile/mg;
	    $mod1=~s/\!OUTFILE\!/$outfile/mg;
	    $mod1=~s/\!WALLTIME\!/$walltime/mg;
	    #
	    $mod1=~s/\!INPUTDIR\!/$datadir/mg;
	    $mod1=~s/\!OUTPUTDIR\!/$datadir/mg;
	    $mod1=~s/\!COMMONDIR\!/$commondir/mg;
	    $mod1=~s/\!TAG\!/$tag/mg;
	    $mod1=~s/\!S\!/$s/mg;
	    $mod1=~s/\!I\!/$i/mg;
	    $mod1=~s/\!T\!/$T/mg;
	    $mod1=~s/\!HOUR\!/$hour/mg;
	    $mod1=~s/\!NCYCLE\!/$ncycle{$T}/mg;
	    $mod1=~s/\!NRUN\!/$nrun/mg;
	    $mod1=~s/\!SWITCH\!/$switch{$T}/mg;
	    $mod1=~s/\!COMB\!/$comb/mg;
	    $mod1=~s/\!COMBCA\!/$combCA/mg;
	    $mod1=~s/\!COMB8CA\!/$comb8CA/mg;
	    $mod1=~s/\!DIST\!/$dist/mg;
	    $mod1=~s/\!DISTL\!/$distL/mg;
	    $mod1=~s/\!EXP\!/$exp/mg;
	    $mod1=~s/\!INIT\!/$init/mg;
	    $mod1=~s/\!PAR\!/$par/mg;
	    $mod1=~s/\!PAIR3\!/$pair3/mg;
	    $mod1=~s/\!PAIR1\!/$pair1/mg;

	    $mod1=~s/\!USER\!/$user/mg;
	    $mod1=~s/\!BINDIR\!/$bindir/mg;

	    $mod1=~s/\!SVMSEQ\!/$svmseq/mg;
	    $mod1=~s/\!TYPE\!/$type/mg;
	    $mod1=~s/\!WCON\!/$Wcon/mg;
	    $mod1=~s/\!FWCON\!/$fWcon/mg;

	    open(job,">$jobname");
	    print job "$mod1\n";
	    close(job);
	    `chmod a+x $jobname`;

	    ########################################
	    #printf "$jobname\n";
	    #system("$jobname");
	    #exit();
	    ########################################


	    ### check whether the job is finished ------->
	    $checktas=`$bindir/checkcas.pl $datadir/out$i$T $datadir/rep1.tra$i$T\.bz2`;
	    printf "$checktas";
	    if($checktas=~/finished/){
		goto pos10;
	    }
=pod
		######### check whether the job is running ##########
		if($jobname=~/record\/(\S+)/){
		    $jobname1=$1;
		    if($qzy=~/$jobname1/){
			printf "$jobname1 is running, neglect the job\n";
			goto pos10;
		    }
	    }

	    ### check number of my submitted jobs to decide whether I can submit new jobs ##
	  pos50:;
	    $jobc=`$bindir/jobcounter.pl $user`;
	    if($jobc=~/njobuser=\s+(\d+)\s+njoball=\s+(\d+)/){
		$njobuser=$1;
		$njoball=$2;
	    }
	    if($njobuser > $njobmax && $njoball >$njoballmax){
		printf "$njobuser > $njobmax && $njoball >$njoballmax, let's wait 2 minutes\n";
		sleep (120);
		goto pos50;
	    }

	    ### submit jobs ----------->
	  pos43:;
	    $bsub=`qsub -q $Q $jobname`;
	    chomp($bsub); 
	    if(length $bsub ==0){
		sleep(20);
		goto pos43;
	    }

	    ### record the jobs submission------>
	    $date=`/bin/date`;
	    chomp($date);
	    open(note,">>$recorddir/note.txt");
	    print note "$jobname\t at $date $bsub\n";
	    close(note);
	    `echo $date > $datadir/simulationjob_$i\_$T`;
	    print "$jobname was submitted.\n";
	    sleep(1);
=cut
		print `$jobname`;
	  pos10:;
	}
    }
  pos_end2:;

    #
    #
    # START CLUSTER.pl
    #
    #

    $clusterdir="$outdir/cluster"; #where the cluster results will be
    $oj="1"; #flag number for different runs, useful when you run multiple jobs for same protein
    #####################################################////////










    ### Please do not change files below unless you know what you are doing #####
    $lib="/nfs/amino-library";

    ########## clustering parameters -------------->
    #$spicker="spicker45d"; #nst=20200
    $spicker="spicker49"; #nst=20200
    $n_para=1; #-1 for ROS; 1 for TASSER
    $n_closc=1; #-1 closc from clustered decoy; 1 closc from all decoys
    $step=2; #1 combo only; 2 combo+stick+model
    $nc5=5; # number of useful clusters
    $n_cut=-1; #n_cut=-1, all decoys; n_cut=35 first 35 decoys

    $qzy=`$bindir/qzy`;

    $clusterdir="$clusterdir";
    $clustermod=`cat $bindir/clustermod`;
    $tratype="*tra*"; #choose what trajectories you want to cluster

    $recorddir="$clusterdir/record";
    `mkdir -p $clusterdir`;
    `mkdir -p $recorddir`;
    open(note,">>$recorddir/note.txt");
    printf "\n\n---------$s-------------\n";

    if($outdir=~/\/(\w+)$/){
	$tag1=$1;
    }
    $tag="CLO$oj\_$tag1\_$s";  #unique for distinguishing jobs
    $tradir="$outdir/$s";
    $tra_in="$clusterdir/$s/tra.in";

    ######### check whether all trajectories are completed #########
    @jobs=<$tradir/simulationjob*>;
    foreach $job(@jobs){
	if($job=~/simulationjob_(\d+)\_(\S+)/){
	    $tra="$tradir/rep1.tra$1$2.bz2";
	    if(-s "$tra" <50){
		printf "Warning: $tra is not complete!\n";
		printf "Therefore, clustering job will not be submitted.\n";
		goto pos01;
	    }
	}
    }

    ########## collect trajectories for 'tra.in' #################
    @tras=<$tradir/$tratype>;
    $n_tra=0;
    foreach $tra(@tras){
	$tra=~/$tradir\/(\S+)/;
	$tra_name=$1;
	if(-s "$tradir/$tra_name" > 50){
	    $n_tra++;
	    $traj{$n_tra}=$tra_name;
	    if($tra_name=~/(\S+)\.bz2/){
		$traj{$n_tra}=$1;
	    }
	}
    }
    goto pos01 if($n_tra<2);  # without trajectories

    ##### check whether the clustering jobs have been done before ########
    # check the number of trajectories in tra.in:
    $number_check="new";
    if(-s "$tra_in"){
	open(tra_old,"$tra_in");
	<tra_old>=~/(\d+)/;
	close(tra_old);
	$n_tra_old=$1;
	if($n_tra <= $n_tra_old){
	    $number_check="finished";
	}
    }
    # check 'rst.dat' (further check):
    $rst_check="new";
    if(-s "$clusterdir/$s/rst.dat"){
	$rstdat=`/bin/cat $clusterdir/$s/rst.dat`;
	$n_in=0;
	for($i=1;$i<=$n_tra;$i++){
	    $n_in++ if($rstdat=~/$traj{$i}/);
	}
	if($n_in == $n_tra){
	    $rst_check="finished";
	}
	if($rstdat=~/Number of clusters\:\s+(\d+)/){
	    $n_cluster=$1;
	}
	$n_cluster=5 if($n_cluster>5);
	if(-s "$clusterdir/$s/combo$n_cluster\.pdb"){
	    $combo="yes";
	}else{
	    $combo="no";
	}
    }
    # decide running:
    printf "\n$clusterdir/$s\n";
    printf "tra_num_tra.in_check=$number_check\n";
    printf "tra_num_rst.dat_check=$rst_check\n";
    printf "number_cluster=$n_cluster\n";
    printf "combo$n_cluster=$combo\n";
    if($number_check eq "finished" && $rst_check eq "finished" && $n_cluster>0 && $combo eq "yes"){
	goto pos01;
    }

    ########## create 'tra.in' #################
    `mkdir -p $clusterdir/$s`;
    open(tra,">$clusterdir/$s/tra.in.tmp");
    printf tra "$n_tra\n";
    for($k=1;$k<=$n_tra;$k++){
	printf tra "$traj{$k}\n";
    }
    close(tra);
    `sort -d $clusterdir/$s/tra.in.tmp > $tra_in`;

    ###
    $jobname="$recorddir/$tag";
    $runjobname="$recorddir/$tag\_run";
    $errfile="$recorddir/err_$tag";
    $outfile="$recorddir/out_$tag";
    $walltime="walltime=20:00:00,mem=3500mb";
    $node="nodes=1:ppn=1";
    ###
    #------- jobname ------>
    $mod=$clustermod;
    $mod=~s/\!ERRFILE\!/$errfile/mg;
    $mod=~s/\!OUTFILE\!/$outfile/mg;
    $mod=~s/\!WALLTIME\!/$walltime/mg;
    $mod=~s/\!NODE\!/$node/mg;

    $mod=~s/\!O\!//mg;
    $mod=~s/\!S\!/$s/mg;
    $mod=~s/\!TAG\!/$tag/mg;
    $mod=~s/\!TRADIR\!/$tradir/mg;
    $mod=~s/\!CLUSTERDIR\!/$clusterdir/mg;
    $mod=~s/\!N_PARA\!/$n_para/mg;
    $mod=~s/\!N_CLOSC\!/$n_closc/mg;
    $mod=~s/\!STEP\!/$step/mg;
    $mod=~s/\!NC5\!/$nc5/mg;
    $mod=~s/\!MODELS\!/$models/mg;
    $mod=~s/\!MM\!/$MM/mg;
    $mod=~s/\!USER\!/$user/mg;
    $mod=~s/\!N_CUT\!/$n_cut/mg;
    $mod=~s/\!SPICKER\!/$spicker/mg;
    $mod=~s/\!BINDIR\!/$bindir/mg;
    $mod=~s/\!COMBO\!/combo/mg;
    open(clusterjob,">$jobname");
    print clusterjob "$mod\n";
    close(clusterjob);
    `chmod a+x $jobname`;

    #printf "chmod a+x $jobname\n";
    #system("$jobname");
    #exit();

    if($jobname=~/record\/(\S+)/){
	$jobname1=$1;
	if($qzy=~/$jobname1/){
	    printf "$jobname1 is running, neglect the job\n";
	    #exit();
	    goto pos01;
	}
    }

    ### submit clustering file #################
  pos424:;
    printf "qsub -q $Q $jobname\n";
    $qsub=`qsub -q $Q $jobname`;
    if(length $qsub ==0){
	sleep(20);
	goto pos424;
    }
    #print "$qsub";
    print note "$qsub";
    print note "$jobname  $temp\n";
    sleep(1);
    printf "$jobname has been submitted.\n";

  pos01:;

}