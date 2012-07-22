#!/usr/bin/perl
use lib qw(/home/toshi/perl/lib);
use strict;
use TumblrDashboardV2;
use TumblrPostV2;
use Encode;
use utf8;
use Config::Pit;
use WWW::Mechanize;
use feature qw( say );

my $pit_account = 'news.azwad.com';

my $offset = 0;
my $num = 20;
my $max = 100;
my $since_id = 27630000000;
my $type = '';
my $delay_time1 = 60;
my $delay_time2 = 1;

open my $fh, '<', 'read.pit' or die 'not exist'; 
while (<$fh>){
	chomp;
	$since_id = $_;
}
close $fh;


my @res;
my $loop = 0;

while ( $loop < 20) {
	say $loop. 'turn';

	my %opt = (
		'limit'				=> $num,
		'offset'			=> $offset,
		'since_id'		=> $since_id,
		'type				'	=> $type,
		'reblog_info'	=> 'false',
		'note_info'		=> 'false',
	);

	my $td = TumblrDashboardV2->new($pit_account);
	print "offset = ". $offset ." num = ". $num . "\n";
	$td->set_option(%opt);
	my $hash  = $td->get_hash;
	if ($td->_err){
		say 'no contents';
		last;
	}
	while (my ($key, $var) =each @$hash){
		my $since_id_tmp = $var->{id};
		if ( $since_id < $since_id_tmp){
			$since_id = $since_id_tmp;
		}
		push (@res, $var);
	}
	++$loop;
}

open $fh, '>', 'read.pit' or die 'not exist';
print $fh $since_id."\n";
close $fh;

my $res = \@res;


	my $dbname = 'tumblr_deduped_check';
	my %deduped = {};
	dbmopen(%deduped, $dbname, 0644);
	my $deduped = \%deduped;

	my %reblog_history = {};
	dbmopen(%reblog_history,'reblog_history',0644);
	my $reblog_history = \%reblog_history;




for my $values (@$res) {


	open my $fh2, '>>', 'tumblrdashboard.txt';
	open my $fh3, '>>', 'dblist.txt';


	my $id = $values->{id};
	my @urls;
 if (exists $deduped{$id}){
		print $deduped{$id} ."is match an old post\n";
		next;
	}else {
		while (my ($number, $url) = each %$deduped){
			push(@urls,$url);
		}
		my $date = $values->{date};
		my $publish_type = $values->{type};
		$_ =  $values->{source} || $values->{caption} ;
		s/<a href="(http.+?)".*>(.+?)<\/a>/$1,$2/ ;
		my $title = $2 || $values->{source_title};
		my $link =  $1 || $values->{link_url} || $values->{source_url} || $values->{post_url};
#			$link =~ s/\;.*?$//;
		my $from = $values->{blog_name};
		print $title." : ".$link ."\n";
		if ( grep{	my $var = $_;
			$var =~ /^$link/ || $link =~ /^$var/ } @urls){
			print "match listed url\n";
			next;
		}else{
			my $text = $values->{text} || $values->{caption} ;
			$deduped{$id} = $link;
			utf8::is_utf8($title)?encode('utf-8',$title):$title;
			utf8::is_utf8($text)?encode('utf-8', $text):$text;
			my $reblog_key = $values->{reblog_key};
			my $note_count = $values->{note_count};
			print $fh3 $id." : ".$from ." : " .$publish_type." : ". $link ." : ". $note_count . " : " .$title;
			print $fh2 $title." : ".$link."\n";
			print $fh2 $date." : ".$publish_type."\n";
			print $fh2 $reblog_key. " : ". $note_count. "\n";
			print $fh2 "\n";
			print $fh2 $text."\n";
			print $fh2 "\n";
			if (decide_post($id, $from, $reblog_key, $note_count, $text, $link, $publish_type)){
				print "reblog this post\n";
				reblog($id, $reblog_key, $link) ;
				print $fh3 " : rebloged\n";
				sleep $delay_time1;
			}else{
				print "don't reblog\n";
				print $fh3 "\n";
				next;
			}
		}
	}

	close $fh2;
	close $fh3;

}


	dbmclose(%deduped);
	dbmclose(%reblog_history);



sub reblog {
	my ($id, $reblog_key, $link) = @_;
	unless (my $res = reblog_post($id,$reblog_key)){
		print "succeed.\n";
		$reblog_history->{$id} = $link;
		return;
	}else{
		print "reblog failed.\n";
		return;
	};
}

sub decide_post {
	my ($id, $from, $reblog_key, $note_count, $text, $link,$publish_type) = @_;
	$text =~ s/<.*?>//g;
	my $text_length = length($text);
	my $decision = 0;
	if ($from eq 'toshi0104'){
		print "can't reblog my post\n";
		return $decision = 0;
	}elsif ( $publish_type !~ s/(quote|regular)//){
		print "don't reblog this content\n";
		return $decision = 0;
	}elsif(($note_count <= 100) && ($text_length >= 500)){
		print "match rule1: notecount is $note_count : text length is $text_length\n";
		$decision = 1;
	}elsif ($text_length >= 1000) {
		print "match rule2: text length is $text_length\n";
		$decision = 1;
	}else{
		print "no match\n";
		return $decision = 0;
	}
	while  (my ($key, $value) = each %$reblog_history) {
		if ($key eq $id) {
			print "$id is already rebloged\n";
			return $decision = 0;
		}elsif ($value eq $link){
			print "$link is already rebloged\n";
			return $decision = 0;
		}else{
			next;
		}
	}
	return $decision;
}

sub reblog_post{
	my ($id, $reblog_key) = @_;
	my $reblog = TumblrPostV2->new($pit_account);
	my %opt = ( 
		'id' => $id,
		'reblog_key' => $reblog_key,
	);

	$reblog->set_option(%opt);

	$reblog->post('reblog');
	return $reblog->_err;
}


