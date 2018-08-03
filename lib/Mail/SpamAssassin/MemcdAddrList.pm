package Mail::SpamAssassin::MemcdAddrList;

use strict;
use warnings;

# ABSTRACT: ne address list for spamassassin auto-whitelist
# VERSION

use Mail::SpamAssassin::PersistentAddrList;
use Mail::SpamAssassin::Util qw(untaint_var);
use Mail::SpamAssassin::Logger;

use Cache::Memcached;

our @ISA = qw(Mail::SpamAssassin::PersistentAddrList);

###########################################################################

sub new {
  my $class = shift;
  $class = ref($class) || $class;
  my $self = $class->SUPER::new(@_);
  $self->{class} = $class;
  bless ($self, $class);
  $self;
}

###########################################################################

sub new_checker {
  my ($factory, $main) = @_;
  my $class = $factory->{class};
  my $conf = $main->{conf};
  my $prefix = $conf->{auto_whitelist_db_prefix};
  my $memcd_server = $conf->{auto_whitelist_db_server};
  my $debug = $conf->{auto_whitelist_db_debug};
  my $exptime = $conf->{auto_whitelist_db_exptime};

  untaint_var( \$memcd_server );

  my $self = {
    'main' => $main,
    'prefix' => defined $prefix ? $prefix : 'awl_',
    'exptime' => defined $exptime ? $exptime : 60*60*24*14, # 14 days
  };

  Mail::SpamAssassin::Plugin::info('initializing connection to memcached server...');
  eval {
    $self->{'memcd'} =  new Cache::Memcached {
      'servers' => [ defined $memcd_server ? $memcd_server : '127.0.0.1:11211', ],
      'debug' => $debug,
      'compress_threshold' => 10_000,
    };
  };
  if( $@ ) {
    die('could not connect to memcached: '.$@);
  }

  bless ($self, $class);
  return $self;
}

###########################################################################

sub finish {
  # Don't do anything so the connection get's cached
}

###########################################################################

sub get_addr_entry {
  my ($self, $addr, $signedby) = @_;

  my $entry = {
    addr => $addr,
  };

  my $hashref = $self->{'memcd'}->get_multi(
    $self->{'prefix'}.$addr.'_count',
    $self->{'prefix'}.$addr.'_score',
  );
  my $count = $hashref->{$self->{'prefix'}.$addr.'_count'};
  my $score = $hashref->{$self->{'prefix'}.$addr.'_score'};
  $entry->{count} =  defined $count ? $count : 0;
  $entry->{totscore} = defined $score ? $score / 1000 : 0;

  dbg("auto-whitelist: memcached-based $addr scores ".$entry->{count}.'/'.$entry->{totscore});
  return $entry;
}

sub add_score {
    my($self, $entry, $score) = @_;

    $entry->{count} ||= 0;
    $entry->{addr}  ||= '';

    $entry->{count}++;
    $entry->{totscore} += $score;

    dbg("auto-whitelist: add_score: new count: ".$entry->{count}.", new totscore: ".$entry->{totscore});

    # We cannot use inc as inc does not allow us to expire the item
    my $hashref = $self->{'memcd'}->get_multi(
      $self->{'prefix'}.$entry->{'addr'}.'_count',
      $self->{'prefix'}.$entry->{'addr'}.'_score',
    );
    my $count = $hashref->{$self->{'prefix'}.$entry->{'addr'}.'_count'};
    my $score_val = $hashref->{$self->{'prefix'}.$entry->{'addr'}.'_score'};
    $count = defined $count ? $count : 0;
    $score_val = defined $score_val ? $score_val : 0;

    $self->{'memcd'}->set( $self->{'prefix'}.$entry->{'addr'}.'_count', int($count) + 1, $self->{'exptime'}) ;
    $self->{'memcd'}->set( $self->{'prefix'}.$entry->{'addr'}.'_score', int($score_val) + int($score * 1000), $self->{'exptime'});

    return $entry;
}

sub remove_entry {
  my ($self, $entry) = @_;

  my $addr = $entry->{addr};
  $self->{'memcd'}->delete( $self->{'prefix'}.$addr.'_count' );
  $self->{'memcd'}->delete( $self->{'prefix'}.$addr.'_score' );

  return;
}

1;
