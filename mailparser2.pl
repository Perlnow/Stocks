#!/usr/bin/perl
#
# Rewrite of mailparser.pl. Alert format change.
# Parse buy/sell alert from IB and store it into transaction table for proper portfolio
# 
# message body is 1 line: 
#          acc      b/s  sym   #  price(s)                  date       time
#   UXXX973 SOLD   G   200@45.34 100@45.34  as of 2012-01-19 10:02:00
#   UXXX973 SOLD   RY  100@53.5             as of 2012-02-21 11:16:38
#   UXXX973 BOT 	  WFC 100@33.84 	   as of 2012-09-04 11:47:01
#
# IB portfolio only (portid=38)
#
#
# Nov 2012 by D.O
# ________________________

use Stocks::Portfolio;
use Stocks::Broker;
use MIME::Parser;
use Data::Dumper qw(Dumper);
$|++;
my $debug = 0;

open LOG, '>/var/log/mailparser.log' or die "could not open log file for writing - $! \n";
print LOG scalar (localtime()), "\n" if $debug;

$parser = MIME::Parser->new( );
$parser->output_to_core(1); # don't write attachments to disk

my $msg = $parser->parse(\*STDIN);
print LOG '**msg**', Dumper $msg if $debug;

my $body = $msg->body;

my $tr = parse_mail();
print LOG '**tr:**', Dumper $tr if $debug;

my $stat = save_tr ($tr) if $tr->{action};

if ($stat) {
  print LOG "transaction saved \n";
} else {
  print LOG "** transaction was not saved - format errors: \n";
  print LOG "__start body__\n", Dumper $body, "\n__end body__";
}

# Check if mail is from correct source and if yes get all the fields
# ARG: none
# RET: %tr{ansaction} hash
#
sub parse_mail {
my ($from, $subject, @flds, $account, %tr );

for (@$body) {

# right line - process
 if ( /^UXXX/ ) {
    @flds = split ('\s+', $_);
    print LOG join '|', @flds, "\n";
    do {print LOG 'wrong number of fields <7 || >9 (',join':', @flds,")\n"; return} unless (@flds >7 && @flds <9);

#    0     1   2     3     4  5     6          7 
# UXXX973 BOT  C 200@35.11 as of 2012-11-29 15:18:18
#    0     1   2     3        4       5   6     7        8 
# UXXX973 SOLD G 200@45.34 100@45.34  as of 2012-01-19 10:02:00

    $account = $flds[0];
    do {print LOG "wrong account ($tr{account})\n"; return} unless $account =~ /^UXXX\d{3}/;
    
    $tr{action} = $flds[1];
    do {print LOG "wrong action ($tr{action}) \n"; return} unless ($tr{action} eq 'BOT' || $tr{action} eq 'SOLD' );
  
    $tr{symbol} = $flds[2];
    do {print LOG "bad symbol ($tr{symbol}\n"; return} unless $tr{symbol} =~ /^\w+$/;

    ($tr{number},$tr{price}) = split ('@',$flds[3]);
    do {print LOG  "bad number ($tr{number})\n"; return} unless $tr{number} =~ /^\d+/;

    do {print LOG "bad price ($tr{price})\n"; return} unless $tr{price} =~ /^\d+\.?\d*$/;

    if ($flds[4] =~ /'@'/) {  # 2 transactions in this email
      ($tr{number2},$tr{price2}) = split ('@',$flds[4]);
      return unless $tr{number2} =~ /^\d+/;
      return unless $tr{price2} =~ /^\d+\.?\d*$/;
      $tr{date} = $flds[7];
      $tr{time} = $flds[8];
    } else {
      $tr{date} = $flds[6];
      $tr{time} = $flds[7];
    }
    do { print LOG "bad date ($tr{date})\n"; return} unless $tr{date} =~ /\d{4}\-\d{2}\-\d{2}/;
    do { print LOG "bad time ($tr{time})\n"; return} unless $tr{time} =~ /\d{2}:\d{2}:\d{2}/;

    printf ("\n ALL GOOD:  acc: '%s' action : '%s' symbol : '%s' number : '%s' price : '%s' date : '%s' time : '%s' \n", 
  	  $account,$tr{action},$tr{symbol},$tr{number},$tr{price},$tr{date},$tr{time});
    
  }
 } # for

 return \%tr
} # parse_mail


# Save transaction into DB table
# ARG: tr hashref
# RET: status 1:success, 0:failure
#
# N.B! For now canadian equities only! For US need to change fees and exchange fields
#
sub save_tr {
   my $tr = shift;

   my %type = ('BOT' => 1, 'SOLD' => -1);
   my $type = $type{$tr->{action}};
   my $descr = $tr->{action} . ' ' . $tr->{number} . ' of ' . $tr->{symbol} . ' @ '. $tr->{price};
   my $descr2 = $tr->{action} . ' ' . $tr->{number2} . ' of ' . $tr->{symbol} . ' @ '. $tr->{price2} if $tr->{number2};
   my $fees = $tr->{number} * 0.01;
   my $exchange = 'NYSE';
   my $market = 'US';
   my $brokerid = 1;  # IB
   my $broker = Stocks::Broker::get( id => $brokerid);
   my $fees = $broker->getFee( shares => $tr->{number} * $type, market => $market);

   my $port = Stocks::Portfolio::get (id => 38); # IB
   my $tro = $port->addTransaction (
                           'ttype'  =>  1,
                           'symbol' => uc($tr->{symbol}),
                           'number' => $tr->{number} * $type,      # -num for sell transactions
                           'price'  => $tr->{price},
                           'exchange' => $exchange,
                           'fx_rate' => 1,
                           'fees'   => $fees,
                           'date'   => $tr->{date} . ' '. $tr->{time},
                           'descr'  => $descr
                         );

  if ($tr->{number2}) {
     my $tro = $port->addTransaction (
                           'ttype'  =>  1,
                           'symbol' => uc($tr->{symbol}),
                           'number' => $tr->{number2} * $type,      # -num for sell transactions
                           'price'  => $tr->{price2},
                           'exchange' => $exchange,
                           'fx_rate' => 1,
                           'fees'   => $fees,
                           'date'   => $tr->{date} . ' '. $tr->{time},
                           'descr'  => $descr2
                         );

  }
  
  return 1 if $tro;
  return;
} # save_tr
