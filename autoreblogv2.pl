#!/usr/bin/perl
use lib qw( /home/toshi/perl/lib );
use strict;
use TumblrDashboardV2;
use TumblrPostV2;
use Encode;
use utf8;
use Config::Pit;
use WWW::Mechanize;
use HTML::Scrubber;
use feature qw( say );
use RegexJapaneseWordList;
use DB_File;
use FindBin;

my $pit_account = 'news.azwad.com';

my $offset = 0;
my $num = 20;
my $max = 100;
my $since_id = 27630000000;
my $type = '';
my $loops = 15;
my $delay_time1 = 180;
my $delay_time2 = 1;

my $script_dir = $FindBin::Bin . '/';
my $read_pit = $script_dir . 'read.pit';
my $reblog_log = $script_dir . 'reblog.log';

open my $fh_read_pit, '<', $read_pit or die 'not exist'; 
while (<$fh_read_pit>){
	chomp;
	$since_id = $_;
}
close $fh_read_pit;


my @res;
my $loop = 0;

while ( $loop < $loops ) {
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
	print "start = $since_id type = $type offset = $offset  num =  $num \n";
	$td->set_option(%opt);
	my $hash  = $td->get_hash;
	if ($td->_err){
		say 'no contents';
		last;
	}
	while (my ($key, $var) = each @$hash){
		push (@res, $var);
	}
	while (my ($key, $var) =each @res){
		my $since_id_tmp = $var->{id};
		if ( $since_id < $since_id_tmp){
			$since_id = $since_id_tmp;
			say "since id is changed to $since_id";
		}
	}
	++$loop;
}

open $fh_read_pit, '>', $read_pit or die 'not exist';
print $fh_read_pit $since_id."\n";
close $fh_read_pit;

my $res = \@res;


my $dbname_deduped = $script_dir . 'tumblr_deduped_check';
my %deduped = {};
dbmopen(%deduped, $dbname_deduped, 0644) or die "could not open $dbname_deduped";

my $dbname_history = $script_dir . 'reblog_history';
my %reblog_history = {};
dbmopen(%reblog_history, $dbname_history,0644) or die "could not open $dbname_history";



for my $values (@$res) {

	my $date = $values->{date};
	my $publish_type = $values->{type};
	my $id = $values->{id};
	my $reblog_key = $values->{reblog_key};
	my $note_count = $values->{note_count};
	my $text = $values->{text} || $values->{caption} ;
	
	$_ =  $values->{source} || $values->{caption} ;
	s/<a href="(http.+?)".*>(.+?)<\/a>/$1,$2/ ;
	my $title = $2 || $values->{source_title};
	my $link =  $1 || $values->{link_url} || $values->{source_url} || $values->{post_url};
	my $from = $values->{blog_name};


	my $match_flag = 0;
	
	while (my ($key, $value) = each %deduped){
		my $regex_value = quotemeta($value);
		my $regex_link = quotemeta($link);
		if (($key eq $id) || ($value =~ /$regex_link/) || ($link =~ /$regex_value/)){
			print "$id : old post or match listed url\n";
			$match_flag = 1;
			last;
		}
	}
		
	if ( $match_flag ) {
		$deduped{$id} = $link;
		next;
	}

	utf8::is_utf8($title)?encode('utf-8',$title):$title;
	utf8::is_utf8($text)?encode('utf-8', $text):$text;

	print $id." : ".$link ."\n";

	$text = format_text($text);

	if (decide_post($id, $from, $reblog_key, $note_count, $text, $link, $publish_type)){
		print "reblog this post -> ";
		reblog($id, $reblog_key, $link, $text);
		sleep $delay_time1;
	}else{
#		open my $log_fh, '>>', $reblog_log;
		print "don't reblog\n";
#		print $log_fh : no reblog\n";
#		close $log_fh;
	}
	$deduped{$id} = $link;

}


dbmclose(%deduped);
dbmclose(%reblog_history);

sub format_text{
        my $text = shift;

        my $scrubber_text = HTML::Scrubber->new();
        $text = $scrubber_text->scrub($text);

        my $regex1 = qr/^.*ID:\w+\s+/;
        $text =~ s/$regex1//;

        chomp ($text);
        $text =~ s/\s+//g;
#        $text = substr($text,0,500);
        return $text;
}


sub decide_post {
	my ($id, $from, $reblog_key, $note_count, $text, $link,$publish_type) = @_;
	my $decision = 0;

	while (my ($key, $value) = each %reblog_history){
		my $regex_value = quotemeta($value);
		my $regex_link = quotemeta($link);
		if (($key eq $id) || ($value =~ /$regex_link/) || ($link =~ /$regex_value/)){
			print "$id : match listed url : ";
#			open my $log_fh, '>>', $eblog_log;
#			print $log_fh "$id : id or $link is listed. ";
#			close  $log_fh;		
			return $decision = 0;
		}
	}

	open my $log_fh, '>>', $reblog_log;
	$text =~ s/<.*?>//g;
	my $text_length = length($text);

	if ($from eq 'toshi0104'){
		print "$id : can't reblog my post. : ";
		$reblog_history{$id} = $link;
#		print $log_fh "$id : $from is my post. ";
		$decision = 0;
	}elsif ( $publish_type !~ s/(quote|regular|text)//){
		print "$id : don't reblog this content : ";
#		print $log_fh "$id : $publish_type is not match. ";
		$decision = 0;
	}elsif ( ratinal_word_check($text) !=1){
		print "$id : including ratinal words. don't reblog this content : ";
#		print $log_fh "$id : $publish_type is not match. ";
		$decision = 0;
	}elsif(($note_count <= 100) && ($text_length >= 500)){
		print "$id : $link\n";
		print "$id : match rule1: note count is $note_count : text length is $text_length. : ";
		print $log_fh localtime . " : $id : $link\n";
		print $log_fh localtime . " : $id : note count is $note_count. text length is $text_length. match rule1. ";
		$decision = 1;
	}elsif ($text_length >= 1000) {
		print "$id : $link\n";
		print "$id : match rule2: text length is $text_length. : ";
		print $log_fh localtime . " : $id : $link\n";
		print $log_fh localtime . " : $id : text length is $text_length. match rule2. ";
		$decision = 1;
	}else{
		print "$id : note count is $note_count. text length is $text_length. not match. : ";
#		print $log "$id : note count is $note_count. text length is $text_length. not match. ";
		$decision = 0;
	}

	close  $log_fh;		
	return $decision;
}

sub reblog {
	my ($id, $reblog_key, $link, $text) = @_;
	my $text2 = substr($text,0,25);
	unless (my $res = reblog_post($id,$reblog_key)){
		print "succeed.\n";
		open my $log_fh, '>>', $reblog_log;
		print $log_fh " : rebloged\n";
		print $log_fh localtime . " : $id : $text2\n";
		close $log_fh;
		$reblog_history{$id} = $link;
		return;
	}else{
		open my $log_fh, '>>', $reblog_log;
		print "failed. \n";
		print $log_fh " : reblog failed.\n";
		print $log_fh localtime . " : $id : $text2\n";
		close $log_fh;
		return;
	};
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

sub ratinal_word_check {
				my $text = shift;
        my $check = RegexJapaneseWordList->new();
				my $decision = 0;
        my $forbidden_words_list = 'forbidden_words_list.yaml';
        my $forbidden_words_list2 = 'forbidden_words_list2.yaml';
                                
        if ($check->regex($text, $forbidden_words_list2)){
#               print "$id : including rational words : ";
#               opem my $log_fh, '>>', $reblog_log;
#               print $log_fh localtime . " : $id : $post_url\n";
#               print $log_fh localtime . " : $id : including rational words : ";
                $decision = 0;
        }else{
                $decision =1;
	}	
}


