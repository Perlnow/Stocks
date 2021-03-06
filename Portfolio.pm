# Stock Portfolio class using Moose
# Maps to Pg portfolio table 
# 
# by Dmitri Ostapenko, d@perlnow.com   

package Stocks::Portfolio;

$VERSION = 1.35;

use strict;
use Moose; 

with qw(Stocks::Base);

use namespace::autoclean;
use Stocks::Types qw( All );
use Stocks::DB;
#use Stocks::User;
use Stocks::Transaction;
use Stocks::TransactionHistory;
use Stocks::DailyTotals;
use Stocks::Utils;
use Stocks::Quote;
use Carp;
#use Smart::Comments;
use List::Util qw(sum);
#use Data::Dumper;


my ($DAY,$MO,$YR) = (localtime())[3..5];
$YR += 1900; $MO++; 
my $USDCAD = Stocks::Utils::get_usdcad || 1;
my $EURCAD = Stocks::Utils::get_eurcad || 1;
    
#   Column    |         Type          |                       Modifiers                        
#-------------+-----------------------+--------------------------------------------------------
# id          | integer               | not null default nextval('portfolio_id_seq'::regclass)
# name        | character varying(31) | not null default ''::character varying
# username    | character varying(75) | not null default ''::character varying
# currency    | currencycodetype      | not null default 'CAD'::character varying
# opt_name    | character varying(31) | not null default ''::character varying
# cashin_base | double precision      | default 0.0
# cashout     | double precision      | default 0.0
# email_flag  | boolean               | default false
# cashin_alt  | double precision      | default 0.0
# currency_alt| currencycodetype      | not null default ''::character varying
# fx_rate     | double precision      | not null default 1.00
# cashonly    | boolean               | default false
# active      | boolean               | not null default true
# brokerid    | integer		      | 
# weight      | double precision      | default 0  !!! not in DB, add and change here

#Indexes:
#    "pkey_port_id" PRIMARY KEY, btree (id)
#    "unique_name_username" UNIQUE, btree (name, username)

#
# Objects of this class will have following attributes:

    has 'id' => (is => 'rw', isa => 'PosInt' );                    			# port id
    has 'name' => (is => 'rw', isa => 'Str');                      			# port name 
    has 'username' => (is => 'rw', isa => 'Str');                  			# username string
    has 'currency' => (is => 'rw', isa => 'CurType', default => 'CAD');			# base currency of the portfolio
    has 'currency_alt' => (is => 'rw', isa => 'Maybe[CurType]');	                # alternative currency
    has 'opt_name' => (is => 'rw', isa => 'Str', default => '');                        # alt port name
    has 'cashin_base' => (is => 'rw', isa => 'Maybe[Num]', default => 0.01);       # Cash deposited in base currency
    has 'cashin_alt' => (is => 'rw', isa => 'Maybe[Num]', default => 0.01);        # Cash deposited in alt currency
    has 'cashout' => (is => 'rw', isa => 'Maybe[Num]', default => 0.01);		# Total Cash transfered out 
    has 'cashonly' => (is => 'rw', isa => 'Bool', default => '0');			# Is it cash portfolio ?
    has 'active' => (is => 'rw', isa => 'Bool', default => '1');			# Is this portfolio active ?
    has 'email_flag' => (is => 'rw', isa => 'Bool', default => '0');	 		# Portfolio email flag 
    has 'brokerid' => (is => 'rw', isa => 'Maybe[Num]', default=> 0 );		        # Broker id from broker table
    has '_assets' => (is => 'rw', isa => 'ArrayRef'); #, default => sub { [] } );	# calculated assets 
    has '_cash' => (is => 'rw', isa => 'Num'); 						# Total Cash
    has '_equity' => (is => 'rw', isa => 'Maybe[Num]', default => 0);   		# Total Equity
    has '_yrgain' => (is => 'rw', isa => 'Maybe[Num]'); 				# This Year's Real Gain/Loss
    has '_curpgain' => (is => 'rw', isa => 'Maybe[Num]'); 				# Current Paper Gain/Loss
    has '_yrdeposits' => (is => 'rw', isa => 'Maybe[Num]'); 				# This Year's total deposits/withdrawals
    has '_TodaysTrades' => (is => 'rw', isa => 'HashRef'); #, default => sub { [] } );	# Today's trades  
    has '_curvalue' => (is => 'rw', isa => 'Maybe[Num]'); 				# Total Current value 
    has 'fx_rate' => (is => 'rw', isa => 'Maybe[PosFloat]', default => 1.00);		# cur fx rate from base to alt currency 
    has '_weight' => (is => 'rw', isa => 'Maybe[PosFloat]', default =>0.00);  # weight for GLD portfolio

__PACKAGE__->meta->make_immutable;
no Moose;

sub _table { 'portfolio' }
sub _trtable { 'transaction' }

sub BUILD {
  my $self = shift;

# compute fields for existing portfolio
  if ($self->found()) {
      if ($self->currency eq 'CAD') {
         $self->fx_rate(1/$USDCAD);
      } elsif ($self->currency eq 'EUR') {
         $self->fx_rate($EURCAD);
      } elsif ($self->currency eq 'USD') {
         $self->fx_rate($USDCAD)
      } else {
         $self->fx_rate(1);
      }

# fx_rate : $self->fx_rate 

#     $self->_assets($self->getAssets());
#     $self->_yrgain($self->getYrGain());
#     $self->_cash($self->getCash);
#     $self->_equity($self->getEquity);
#     $self->_yrdeposits($self->getYrDeposits);
#     $self->_TodaysTrades($self->getTodaysTrades);
#     $self->_curvalue($self->getCurrentValue);
  }

  return $self;
}

# Pseudo attributes: let Non-DB attributes be called as normal
sub assets {
  my $self = shift;
  return $self->getAssets;
}

sub cashin {
  my $self = shift;
  my $alt_in_base = 0;
  $alt_in_base = $self->cashin_alt * $self->fx_rate if $self->cashin_alt > 1;
  return $self->cashin_base + $alt_in_base;
}

sub cash {
  my $self = shift;
  return $self->getCash;
}

sub equity {
  my $self = shift;
  return $self->getEquity;
}

sub weight {
  my $self = shift;
  return $self->getWeight;
}

sub yrgain {
  my $self = shift;
  return $self->getYrGain;
}

sub curpgain {
  my $self = shift;
  my $gains = $self->getPprGains;
  my $ttl = 0;
  map { $ttl += $_ } values %$gains;
  return $ttl
}

sub TodaysTrades {
  my $self = shift;
  return $self->getTodaysTrades
}

sub curvalue {
  my $self = shift;
  return $self->getCurrentValue;
}

sub prevvalue {
  my $self = shift;
  return $self->getPrevVal;
}

# Get portolio with given id
# ARG: id || username && name
# RET: obj

sub get {
   my (%arg) = @_;
   my $id = $arg{id};
   my $username = $arg{username};
   my $name = $arg{name}; 
   my $where;

   croak "id or username & name are required " unless ($id || ($username && $name));

   if ( $id ) {
      $where .= 'id='.$id;
   } else {
      $where .= "username='$username' AND name='$name'";
   }

  my $row = Stocks::DB::select ( table => _table(), 
   			      	 where => $where,
			         limit => 1
			        );

  return unless ref $row;
  return __PACKAGE__->new( $row );

} #get

# Verify that portfolio belongs to the user
# Object method
# ARGS: user obj
# RET: confirmed id or undef

sub assert_ownership {
  my ($self, $user) = @_;
  my $id = $self->id;
  my $username = $user->username;

  return Stocks::DB::select( table => _table(),
  			     fields => [qw(id)],
			     where => "id=$id AND username='$username'",
			     returns => 'scalar',
			   );  
} # assert_ownership


# Delete portfolio and all of its transactions from the database
# ARG: none
# RET: none

sub Delete {
   my $self = shift;

   croak "'id' must be set" unless $self->id;

   $self->delete(); 
   $self->delete_transactions();
}

# Delete all portfolio's transactions
# ARG: none (id must be set) 
# RET: none

sub delete_transactions {
  my $self = shift;

  croak "'id' must be set" unless $self->id;
  
  Stocks::Transaction::delete_all ( portid => $self->id );

} # delete_transactions

# Get all portfolios for this user
# Class method
# ARG: username 
#      activeonly => 0 | 1  include insactive portfolios ?
#      equityonly => 0 | 1  only equity portfolios ?
#      cashonly   => 0 | 1  only cash portfolios ?
#      type       => all | cash | stocks
#      by => 'id' | 'name' | 'opt_name'
# RET: id => name|opt_name hashref
#
sub getAll {
    my %arg = @_;
    my $by = lc $arg{by} if $arg{by};
    my $username = $arg{username};
    my $and = '';
    $and .= " AND active='t'" if $arg{"activeonly"};

    if ($arg{"cashonly"} || ($arg{"type"} and $arg{"type"} eq 'cash')) {
         $and .= " AND cashonly='t'";
    }

    if ($arg{equityonly} || ($arg{"type"} and $arg{"type"} eq 'stocks')) {
       $and .= " AND cashonly='f'";
    }

    $by ||= 'id';

### Port and : $and
    croak "'username' is required" unless $username;

    my $rows = Stocks::DB::select ( table => _table(),
    				    where => "username='$username' ".$and,
     		  	    	    order_by => 'name'
		   	           );
    
    return unless $rows->[0];

    if ( $by eq 'name' ) {
       return {map { $_->{name}, $_->{id}} @$rows}
    } else {
       return {map { $_->{id}, $_->{name}} @$rows}
    }
} # getAll

# Get transaction count for this portfolio
# Object method
# ARG: none
# RET: scalar

sub getTrCount {
    my $self = shift;

    croak "'id' must be set" unless $self->id;

    return Stocks::Transaction::getCount ( portid => $self->id);

} # getTrCount

# Get transaction count for this portfolio history
# Object method
# ARG: none
# RET: scalar

sub getHTrCount {
   my $self = shift;

   croak "'id' must be set" unless $self->id;

   return Stocks::TransactionHistory::getCount ( portid => $self->id);
}

# Get oldest transaction of give type
# obj method
# ARG: ttype (tr type) opt
# RET: transaction obj

sub getOldestTr {
  my ($self, %arg) = @_;
  my $ttype = $arg{ttype};
  
  croak "'id' must be set" unless $self->id;

  return Stocks::Transaction::getOldest (portid => $self->id, ttype => $ttype );

} # getOldestTr

# Get date of the latest transaction in transactions table
# Object method
# ARG: none
# RET: transaction object

sub getLatestTr {
  my ($self, %arg) = @_;
  my $ttype = $arg{ttype};
  
  croak "'id' must be set" unless $self->id;

  return Stocks::Transaction::getLatest (portid => $self->id, ttype => $ttype);

} #getLatestTr


# Get oldest transaction of the given type from history table
# obj method
# ARG: ttype (tr type) opt
# RET: transaction obj

sub getOldestHTr {
  my ($self, %arg) = @_;
  my $ttype = $arg{ttype};
  
  croak "'id' must be set" unless $self->id;

  return Stocks::TransactionHistory::getOldest (portid => $self->id, ttype => $ttype );

} # getOldestHTr

# Get latest transaction of the given type from history table
# Object method
# ARG: none
# RET: date str

sub getLatestHTr {
  my ($self, %arg) = @_;
  my $ttype = $arg{ttype};
  
  croak "'id' must be set" unless $self->id;

  return Stocks::TransactionHistory::getLatest (portid => $self->id, ttype => $ttype);

} #getLatestHTr

# Get equity+cash for this port on latest trading day
# ARG: none
# RET: scalar

sub getCurVal {
  my ($self, %arg) = @_;

  croak "'id' must be set" unless $self->id;

  my $ttl = Stocks::DailyTotals::getLast( portid=> $self->id, year => $arg{year});
  return ($ttl->cash + $ttl->equity) if ref $ttl;
}

# Get equity+cash for this portfolio on previous trading day
# ARG: none
# RET: scalar

sub getPrevVal {
  my $self = shift;
  croak "'id' must be set" unless $self->id;

  my $ttl = Stocks::DailyTotals::getPrev( portid=> $self->id);
  return ($ttl->cash + $ttl->equity) if ref $ttl;
}

# Get totals for every day of a given month/year or current month by def
# ARG: year, month [1-12] (opt)
# RET: hashref

sub getMonth {
  my ($self,%arg) = @_;
  croak "'id' must be set" unless $self->id;

  return Stocks::DailyTotals::getMonth( portid => $self->id, year => $arg{year}, month => $arg{month} );
}

# Get totals for given month/year or current month by def
# ARG: year, month [1-12] (opt)
# RET: DailyTotals obj

sub getMonthTotals {
  my ($self,%arg) = @_;
  croak "'id' must be set" unless $self->id;

  return Stocks::DailyTotals::getMonthTotals( portid => $self->id, year => $arg{year}, month => $arg{month} );
}

# Get latest totals for this portfolio
# ARG : year, month [opt] cur by def
# RET: DailyTotals obj

sub getLastTotals {
  my ($self,%arg) = @_;
  croak "'id' must be set" unless $self->id;

  return Stocks::DailyTotals::getLast( portid => $self->id );
}

# Get totals for this portfolio on previous trading day
# ARG : year, month [opt] cur by def
# RET: DailyTotals obj

sub getPrevTotals {
  my ($self,%arg) = @_;
  croak "'id' must be set" unless $self->id;

  return Stocks::DailyTotals::getPrev( portid => $self->id );
}

# Get totals for this portfolio in given quarter/year
# ARG :  year : [opt] current by def
#        qtr  : [opt] cur by def
# RET: DailyTotals obj

sub getQtrTotals {
  my ($self,%arg) = @_;
  croak "'id' must be set" unless $self->id;
  my $qtr = $arg{qtr};   # undef is ok here
  my $year = $arg{year}; # undef is ok here

  return Stocks::DailyTotals::getQtrTotals(portid => $self->id, qtr => $qtr, year => $year);

}

# Get total of deposits for given day; assume today if no date is given
# ARG: date (opt)
# RET: scalar
#
sub getDayTotalDep {
  my ($self, %arg) = @_;
  $arg{date} ||= Stocks::Utils::today();

  croak "'id' must be set" unless $self->id;
  croak "need date (yyyy-mm-dd)" unless $arg{date} =~ /^\d{4}-\d{1,2}-\d{1,2}$/; 
  
  my $where =  'portid='.$self->id." AND ttype=0 AND DATE(date) = '$arg{date}'";

  return Stocks::DB::select( table => _trtable(),
   		 	     fields => [('SUM(number) AS ttl')],
  		             where => $where,
			     returns => 'scalar'
			    );

} # getDayTotalDep

# Get total of cash transfers for given day; assume today if no date is given
# ARG: date (opt)
# RET: scalar
#
sub getDayTotalTransf {
  my ($self, %arg) = @_;
  $arg{date} ||= Stocks::Utils::today();

  croak "'id' must be set" unless $self->id;
  croak "need date (yyyy-mm-dd)" unless $arg{date} =~ /^\d{4}-\d{1,2}-\d{1,2}$/; 
  
  my $where =  'portid='.$self->id." AND ttype=4 AND DATE(date) = '$arg{date}'  AND number>0 ";

  return Stocks::DB::select( table => _trtable(),
   		 	     fields => [('SUM(number) AS ttl')],
  		             where => $where,
			     returns => 'scalar'
			    );

} # getDayTotalTransf

# Get total of deposits for given week; assume this week if no wk# is given
# ARG: wk : 0..52 (opt) ( most recent week for now)
# RET: scalar
#
sub getWeekTotalDep {
  my ($self, %arg) = @_;

  croak "'id' must be set" unless $self->id;
#  croak "need week (1..52)" unless $arg{week} >0 and $arg{week} < 53; 
  
  my $where =  'portid='.$self->id." AND ttype=0 AND DATE(date) >= date_trunc('week', NOW())";

  return Stocks::DB::select( table => _trtable(),
   		 	     fields => [('SUM(number) AS ttl')],
  		             where => $where,
			     returns => 'scalar'
			    );

} # getWeekTotalDep

# Get total of deposits for given month (current by def)
# ARG: year [opt] <nnnn>
#      month (1..12)
# RET: scalar
#
sub getMonthTotalDep {
  my ($self, %arg) = @_;

  my ($year) = $arg{year} || $YR;
  my $mon = $arg{month} || $MO;
  my $nextmon = $mon < 12 ? $mon + 1 : 1;

  my $where =  'portid='.$self->id." AND ttype=0 AND date>= '$year-$mon-01' ";

  $year++ if $mon > 11;
  $where .= "AND date < '$year-$nextmon-01'";

  my $ttl = Stocks::DB::select( table => _trtable(),
   				fields => [('SUM(number) AS ttl')],
  		                where => $where,
				returns => 'scalar'
			       );

  return $ttl
} # getMonthTotalDep


# Get total cash transfers in for given month (current by def)
# ARG: year [opt] <nnnn>
#      month (1..12)
# RET: scalar
#
sub getMonthTotalTransf {
  my ($self, %arg) = @_;

  my ($year) = $arg{year} || $YR;
  my $mon = $arg{month} || $MO;
  my $nextmon = $mon < 12 ? $mon + 1 : 1;

  my $where =  'portid='.$self->id." AND ttype=4 AND date>= '$year-$mon-01' ";

  $year++ if $mon > 11;
  $where .= "AND date < '$year-$nextmon-01'";

  my $ttl = Stocks::DB::select( table => _trtable(),
   				fields => [('SUM(number) AS ttl')],
  		                where => $where,
				returns => 'scalar'
			       );

  return $ttl
} # getMonthTotalTransf

# Get total deposits for given timeframe
# object method
# ARG: tframe
# RET: scalar

sub getDeposits {
    my ($self, %arg) = @_;

    croak 'portfolio obj is required' unless $self->id;

    my $tframe = $arg{tframe} || 'all';
    my $dtrange = Stocks::Utils::getDateRange( $tframe );
    my $and = '';
    $and = " AND date <= '".$dtrange->{edate}."'" if $dtrange->{edate};

    my $qry = "SELECT SUM(number) FROM transaction WHERE portid=".$self->id." AND ttype=0 AND date>='"
               . $dtrange->{sdate} ."' ". $and;

    return Stocks::DB::select ( sql => $qry, returns => 'scalar') || 0;
}

# Get All transactions of given type for this portfolio
# ARG: symbol: get all transactions for this symbol (opt)
#      exchange : exchange (opt, required if symbol is given)
#      ttype: transaction type to get 
#      sort: which field to sort on;
#      order: asc/desc
#      sdate,edate: start/end y-m-d dates
# RET: transactions arrayref

sub getTransactions {
    my ($self,%arg) = @_;
    my @otr;

    my $sort = $arg{sort} || 'date';;
    my $order = $arg{order} || 'desc';
    my $symbol = $arg{symbol};
    my $exchange = $arg{exchange};
    my $ttype = -1;
    $ttype = $arg{ttype} if defined $arg{ttype};

    my $sdate = $arg{sdate};
    my $edate = $arg{edate};

    my $and;
    $and .= "AND symbol='$symbol' " if $symbol;
    $and .= "AND exchange='$exchange' " if $exchange;
    $and .= "AND date>='$sdate' " if $sdate;
    $and .= "AND date <= '$edate' " if $edate;
    $and .= "AND ttype='$ttype' " if  $ttype > -1;  # 0 - cash
 
    my $qry = "SELECT * FROM transaction WHERE portid=".$self->id.' '.$and." ORDER BY $sort $order";

    my $rows = Stocks::DB::select ( sql => $qry );

    foreach my $tr (@$rows) {
        push @otr, Stocks::Transaction->new ( $tr );
    }

    return \@otr;

} # getTransactions

# Get All transactions of given type from history table for this portfolio
# ARG: symbol: get all transactions for this symbol
#      ttype: transaction type to get
#      sort: which field to sort on;
#      order: asc/desc
#      sdate,edate: start/end y-m-d dates
# RET: transactions arrayref

sub getHistory {
    my ($self,%arg) = @_;

    my $sort = $arg{sort} || 'date';;
    my $order = $arg{order} || 'desc';
    my $symbol = $arg{symbol};
    my $ttype = $arg{ttype};
    $ttype = -9 if $ttype eq '';

    my $sdate = $arg{sdate};
    my $edate = $arg{edate};

    my ($sth, $tr, @otr );

    my $and;
    $and .= "AND symbol='$symbol' " if $symbol;
    $and .= "AND date>='$sdate' " if $sdate;
    $and .= "AND date <= '$edate' " if $edate;
    $and .= "AND ttype='$ttype' " if  $ttype > -1;  # 0 - cash

    my $qry = "SELECT * FROM transaction_history WHERE portid=".$self->id.' '.$and." ORDER BY $sort $order";
    my $rows = Stocks::DB::select ( sql => $qry, 
    			     	    returns => 'array' 
			  	   ); 
    
    return $rows
} #getHistory

# Get all unique symbols in this portfolio. Active positions only if activeOnly is set
# Object method
# ARG: activeOnly => 0/1 (opt). All symbols by default
#      options => 0/1 (opt). options symbols shown by default
# RET: arrayref of (symbol,exchange,number)

sub getSymbols {
    my ($self,%arg) = @_;
    my $and = '';
    my $or = ' OR ttype=7 OR ttype=8 ';
    $and = ' AND ttlnumber>0 ' if $arg{'activeOnly'};
    $or = ' ' if ($arg{'options'} == 0);

    my $qry = 'SELECT DISTINCT symbol,exchange,SUM(number) as ttlnumber FROM transaction WHERE (ttype=1 OR ttype=5 '.$or.') AND portid='.$self->id.$and.' GROUP BY symbol,exchange ORDER BY symbol ';

    return Stocks::DB::select ( sql => $qry );
} # getSymbols

# Get unique symbols from history table. Active positions only if activeOnly is set
# ARG: activeOnly => 0/1 (opt). All symbols by default
# RET: arrayref of (symbol,exchange)

sub getHSymbols {
    my ($self,%arg) = @_;
    my $having = 'HAVING SUM(number)>0' if $arg{'activeOnly'};

    my $qry = "SELECT DISTINCT symbol,exchange FROM transaction_history WHERE portid=".$self->id.' AND ttype=1 GROUP BY symbol,exchange ORDER BY symbol'.$having;
    
    return Stocks::DB::select (sql => $qry ); 
} # getHSymbols

# Get Total Equity for this portfolio
# Object method
# EFFECTS: sets _equity private attr
# ARG: none
# RET: Total ACB

sub getEquity {
  my $self = shift;

  croak "'id' is required" unless $self->id;
  
  return $self->_equity if $self->_equity;

  my $qry = "SELECT SUM(equity) FROM transaction WHERE portid=".$self->id.' AND (ttype=1 OR ttype=5)';

  my $equity = Stocks::DB::select ( sql => $qry, returns => 'scalar');
  $self->_equity ($equity);

  return $equity

} # getEquity

# Get full list of assets in this portfolio
# object method
# ARG: none
# RET: asset structure for each unique symbol
    
sub getAssets {
   my $self = shift;

   croak "'id' is required" unless $self->id;

   return $self->_assets if $self->_assets;

   my $qry = "SELECT "
                . " symbol, exchange,"
		. " DATE(MAX(date)) AS latest_date,"
                . " SUM(number) AS number,"
                . " SUM(equity) AS equity,"
                . " abs(SUM(equity) / SUM(number)) AS acb,"
                . " SUM(cash) AS cash,"
                . " SUM(equity + cash) AS realgain,"  # + fees to include
		. " SUM(fees) AS fees"
                . " FROM transaction "
                . " WHERE portid=".$self->id." AND (ttype = 1 OR ttype = 5 OR ttype = 7 OR ttype = 8)"
		. " GROUP BY symbol,exchange HAVING SUM(number)<>0"
		. " ORDER BY symbol"; 

   my $assets = Stocks::DB::select ( sql => $qry );

# adjust for position transfers: 
   $qry = 'SELECT symbol, SUM (cash+equity) AS value FROM transaction WHERE portid='.$self->id.' AND ttype=5 GROUP BY symbol HAVING SUM(equity+cash)!=0;';
   my $tfs = Stocks::DB::select ( sql => $qry);
   my %tfs =  map { $_->{symbol}, $_->{value} } @$tfs;

   my $symbol;

   foreach my $ass ( @$assets ) {
      $symbol = $ass->{symbol};
      next unless $tfs{$symbol};
      $ass->{realgain} -= $tfs{$symbol};
   }

   $self->_assets($assets);

   return $assets;
} # getAssets


# get portfolio current value based on latest quotes for each symbol
# convert to base currency, add cash

sub getCurrentValue {
    my $self = shift;
    my ($quote, $fx_rate, $ttlval);
    $ttlval = 0;
    
    croak "'id' is required" unless $self->id;

# current value in CDN for gold portfolios
    if ($self->currency() eq 'GLD') {
       return ($self->getWeight() * Stocks::Utils::get_gold_gr() * $USDCAD);
    }

    foreach my $ass ( @{$self->assets} ) {
       $quote = Stocks::Quote::get ( symbol => $ass->{symbol}, exchange => $ass->{exchange} );
       next unless $quote;

       $fx_rate = Stocks::Utils::getFX ( portcurrency => $self->currency, symexchange => $ass->{exchange});
       $ttlval += $quote->last * $ass->{number} * $fx_rate ;
    }

   my $curval = $ttlval + $self->cash();
   $self->_curvalue($curval);

   return $curval
} # getCurrentValue

# Calculate real gain by symbol for given period
# ARG: sdate, edate 
# RET: hash sym->gain
#
sub getRealGain {
   my ($self,%arg) = @_;
   my $and = '';

   croak "'id' is required" unless $self->id;

   my $sdate = $arg{sdate} || $YR.'-01-01';
   my $edate = $arg{edate};
      $and = " AND DATE(date) <= '$edate'" if $edate;
   
   my $qry = "SELECT "
	     . " symbol, SUM(equity+cash) AS realgain"
             . " FROM transaction "
             . " WHERE portid=".$self->id." AND ttype = 1 AND cash>0 AND DATE(date) >= '$sdate' $and "
	     . " GROUP BY symbol ORDER by symbol";

   my $rows = Stocks::DB::select ( sql => $qry); #, returns => 'array');
   return map { $_->{symbol}, $_->{realgain} } @$rows;

} # getRealGain

# Calculate paper gain by symbol for given period
# ARG: none 
# RET: hash sym->gain

sub getPprGains{
   my ($self,%arg) = @_;
   my ($quote,$fx_rate,$gain,%gains);

   foreach my $ass ( @{$self->assets} ){
     next unless $ass->{number} > 0; 

     $quote = Stocks::Quote::get ( symbol => $ass->{symbol}, exchange => $ass->{exchange} );
     next unless defined $quote && $quote->last;

     $fx_rate = Stocks::Utils::getFX (portcurrency => $self->currency, symexchange => $ass->{exchange});
     $gains{$ass->{symbol}} = ($quote->last * $ass->{number} - $ass->{equity}) * $fx_rate;
  }

return \%gains

} # getPprGains

# get equity by symbol in this portfolio
# ARG: none
# RET: hash symbol => equity

sub getEquityBySymbol { 
    my $self = shift;

    my $qry = 'SELECT symbol,sum(equity) AS equity FROM transaction WHERE portid='.$self->id.' AND (ttype=1 or ttype=5) GROUP BY SYMBOL HAVING sum(number)<>0';
 
    my %equity = map { $_->[0], $_->[1] } @{Stocks::DB::select ( sql => $qry, returns => 'array' )};

print join':', %equity;

    return \%equity;
}

# Get total equity for this portfolio
# ARG: none
# RET: scalar

sub getTtlEquity {
   my $self = shift;
   
   my $equity = $self->getEquityBySymbol();
   return sum(values %$equity) if ref $equity;
   return
}

# Get portfolio value on last trading day of the last year
# ARG: none
# RET: scalar

sub getLyrValue {
   my $self = shift;

   my $lyr = Stocks::Utils::lastyr();
   my $obj = Stocks::DailyTotals::getMonthTotals (portid => $self->id, year => $lyr, month => 12);

   return $obj->equity() + $obj->cash();
}

# Get total paper P/L for this portfolio
# ARG: none
# RET: scalar

sub getTtlPprGain {
   my $self = shift;

   my $pprgains = $self->getPprGains();
   return sum(values %$pprgains) if ref $pprgains;
}

# Total YTD Real Gain for this portfolio 
# object method
# ARG: none
# ret: scalar
# EFF: sets _yrgain if not set yet

sub getYrGain {
   my $self = shift;

   return $self->_yrgain if $self->_yrgain;
   my $yrgain = $self->getTtlGain();
   $self->_yrgain($yrgain);

   return $yrgain
}

# Calculate total real gain for given period
# obj method
# ARG: sdate : start date
#      edate : end date (opt) def now
# RET: hash sym->gain
#
sub getTtlGain {
   my ($self,%arg) = @_;
   my $sdate = $arg{sdate} || $YR.'-01-01';
   my $edate = $arg{edate} || undef;

   croak "Not an object call" unless $self->isa(__PACKAGE__);

   my $where = "portid=".$self->id." AND (ttype = 1 or ttype=7 or ttype=8) AND DATE(date) >= '$sdate'"; 

   $where .= " AND DATE(date) <= '$edate'" if $edate;
   
   my $ttlgain = Stocks::DB::select ( table => _trtable(),
   				      fields => [('SUM(equity+cash) AS realgain')],
				      where => $where,
   				      returns => 'scalar',
				    );

   return $ttlgain || 0;

} # getTtlGain

# Calculate total cash position for this portfolio in base currency for this portfolio
# ARG: none
# RET: ttl cash

sub getCash {
   my $self = shift;
   my ($qry,$base_cash);
   my $alt_cash=0.01;

   croak "Not an object call" unless $self->isa(__PACKAGE__);

   return $self->getCurrentValue() if ($self->currency eq 'GLD');
   return $self->_cash if $self->_cash();  # already computed
   
   if ( $self->cashin_alt > 1) {
      $qry = "SELECT SUM(cash) FROM transaction WHERE portid=" .$self->id. " AND exchange='TSX'";
      $base_cash = Stocks::DB::select ( sql => $qry, returns => 'scalar');
      $qry = "SELECT SUM(cash) FROM transaction WHERE portid=" .$self->id. " AND exchange<>'TSX'";
      $alt_cash = Stocks::DB::select ( sql => $qry, returns => 'scalar') || 0.01;
   } else {
      $qry = "SELECT SUM(cash) FROM transaction WHERE portid=" .$self->id;
      $base_cash = Stocks::DB::select ( sql => $qry, returns => 'scalar');
   }

   my $ttlcash = $base_cash + $alt_cash * 1/$self->fx_rate;
   $self->_cash($ttlcash);

   return $ttlcash;
} # getCash

# Returns total weight for gold portfolio
# ARG : none
# RET : scalar

sub getWeight {
   my $self = shift;
   my $qry;

   croak "Not an object call" unless $self->isa(__PACKAGE__);
   return 0 unless $self->currency() eq 'GLD';

   return $self->_weight if $self->_weight();  # already computed
   
   $qry = "SELECT SUM(weight) FROM transaction WHERE portid=" .$self->id;
   my $ttlweight = Stocks::DB::select ( sql => $qry, returns => 'scalar');
   
   $self->_weight($ttlweight);

   return $ttlweight;

}# getWeight

# Get total number of shares,real gain and average price for today's trades, return hash by symbol
# ARG: none 
# RET: symbol => {number,gain,avgprice} hashref

sub getTodaysTrades {
   my $self = shift;

   croak "Not an object call" unless $self->isa(__PACKAGE__);

   return $self->_TodaysTrades if $self->_TodaysTrades;

# Buys:
   my $qry = 'SELECT symbol,SUM(number) AS number, AVG(price) AS avgprice FROM transaction '
   	    ." WHERE portid=".$self->id." AND number>0 AND ttype=1 AND DATE(date) = DATE(now()) GROUP BY symbol";

   my $rows = Stocks::DB::select (sql => $qry);

   my %buys = map { $_->{symbol}, $_ } @$rows;

# Sells:
   $qry = 'SELECT symbol,SUM(number) AS number, AVG(price) AS avgprice FROM transaction '
   	    ." WHERE portid=".$self->id." AND number<0 AND ttype=1 AND DATE(date) = DATE(now()) GROUP BY symbol";

   $rows = Stocks::DB::select (sql => $qry);
   my %sells = map {$_->{symbol}, $_} @$rows;

   my $tdtr =  {('buys' => \%buys, 'sells' => \%sells)};
   $self->_TodaysTrades( $tdtr );

   return $tdtr;
} # getTodaysTrades

# Get individual trades for today
# ARG: none 
# RET: arrayref

sub getAllTodayTrades {
   my $self = shift;
   my $portid = $self->id;

   croak "Not an object call" unless $self->isa(__PACKAGE__);
   
   my $qry = "SELECT * FROM transaction WHERE portid=$portid AND ttype=1 AND DATE(date) = DATE(now()) ORDER BY date";
   return Stocks::DB::select (sql => $qry);
}

# Return number of trades for given date range/portfolio
# ARG: tframe
# RET: scalar

sub getTradesNum {
    my ($self, %arg) = @_;
   
    croak "Not an object call" unless $self->isa(__PACKAGE__);
    croak "need timeframe " unless $arg{tframe};

    return scalar @{$self->getTrades ( tframe => $arg{tframe})};
}


# Get trades for given date range/[symbol]  (ttype = 1,7,8, no DRIP)
# ARG: tframe   : timeframe (see Utils::getTimeFrameNames for defs) ytd by def
#      [symbol] : limit query to this symbol  (sym:exch format; TSX if no exchange )
#      show_drip : 0 : drip excluded; 1: drip included; 2 drip only  (shows stock purchases under DRIP agreement)
# RET: arrayref 

sub getTrades {
    my ($self, %arg) = @_;
    my $tframe = $arg{tframe} || 'ytd';
    my $symbol = $arg{symbol} || undef;

    croak "Not an object call" unless $self->isa(__PACKAGE__);
    my $range = Stocks::Utils::getDateRange ( $tframe );
 
    return Stocks::Transaction::getTrades (
                                  portid => $self->id,
                                  sdate  => $range->{sdate}, 
                                  edate  => $range->{edate}, 
				  symbol => $symbol,
				  show_drip => $arg{show_drip}
                                );
} # getTrades


# Calculate total of dividends for given date range
# ARG: tframe : timeframe (see Utils::getTimeFrameNames for defs) ytd by def
# RET: scalar

sub getDividends {
    my ($self, %arg) = @_;
    my $tframe = $arg{tframe} || 'ytd';

    croak "Not an object call" unless $self->isa(__PACKAGE__);
    my $range = Stocks::Utils::getDateRange ( $tframe );

    return Stocks::Transaction::getDividends (
                                  portid => $self->id,
                                  sdate  => $range->{sdate}, 
                                  edate  => $range->{edate}, 
                                );
} # getDividends


# Calculate total of interest for given date range
# ARG: tframe : timeframe (see Utils::getTimeFrameNames for defs) ytd by def
# RET: scalar

sub getInterest {
    my ($self, %arg) = @_;
    my $tframe = $arg{tframe} || 'ytd';

    croak "Not an object call" unless $self->isa(__PACKAGE__);
    my $range = Stocks::Utils::getDateRange ( $tframe );

    return Stocks::Transaction::getInterest (
                                  portid => $self->id,
                                  sdate  => $range->{sdate}, 
                                  edate  => $range->{edate}, 
                                );
} # getInterest

# Calculate total of transaction fees for given date range
# ARG: tframe : timeframe (see Utils::getTimeFrameNames for defs) ytd by def
# RET: scalar

sub getFees {
    my ($self, %arg) = @_;
    my $tframe = $arg{tframe} || 'ytd';

    croak "Not an object call" unless $self->isa(__PACKAGE__);
    my $range = Stocks::Utils::getDateRange ( $tframe );

    return Stocks::Transaction::getFees (
                                  portid => $self->id,
                                  sdate  => $range->{sdate}, 
                                  edate  => $range->{edate}, 
                                );
} # getFees

# Calculate total transaction fees for given date range grouped by symbol
# ARG: tframe : timeframe (see Utils::getTimeFrameNames for defs) ytd by def
# RET: scalar

sub getFeesBySymbol {
    my ($self, %arg) = @_;
    my $tframe = $arg{tframe} || 'ytd';

    croak "Not an object call" unless $self->isa(__PACKAGE__);
    my $range = Stocks::Utils::getDateRange ( $tframe );

    return Stocks::Transaction::getFeesBySymbol (
                                  portid => $self->id,
                                  sdate  => $range->{sdate}, 
                                  edate  => $range->{edate}, 
                                );
}

# Get non-transaction fees for this portfolio/date range
# ARG: tframe : timeframe (see Utils::getTimeFrameNames for defs) ytd by def
# RET: scalar

sub getOtherFees {
    my ($self, %arg) = @_;
    my $tframe = $arg{tframe} || 'ytd';

    croak "Not an object call" unless $self->isa(__PACKAGE__);
    my $range = Stocks::Utils::getDateRange ( $tframe );

    return Stocks::Transaction::getOtherFees (
                                  portid => $self->id,
                                  sdate  => $range->{sdate}, 
                                  edate  => $range->{edate}, 
                                );
}

# Calculate total of position transfers for a given date range
# ARG: tframe : timeframe (see Utils::getTimeFrameNames for defs) ytd by def
# RET: scalar

sub getPosTransfers {
    my ($self, %arg) = @_;
    my $tframe = $arg{tframe} || 'ytd';

    croak "Not an object call" unless $self->isa(__PACKAGE__);
    my $range = Stocks::Utils::getDateRange ( $tframe );

    return Stocks::Transaction::getTransfers (
                                  type   => 'pos',
                                  portid => $self->id,
                                  sdate  => $range->{sdate}, 
                                  edate  => $range->{edate}, 
                                );
} # getPosTransfers

# Calculate total of cash transfers for a given date range
# ARG: tframe : timeframe (see Utils::getTimeFrameNames for defs) ytd by def
# RET: scalar

sub getCashTransfers {
    my ($self, %arg) = @_;
    my $tframe = $arg{tframe} || 'ytd';

    croak "Not an object call" unless $self->isa(__PACKAGE__);
    my $range = Stocks::Utils::getDateRange ( $tframe );

    return Stocks::Transaction::getTransfers (
                                  type   => 'cash',
                                  portid => $self->id,
                                  sdate  => $range->{sdate}, 
                                  edate  => $range->{edate}, 
                                );
} # getCashTransfers

# Calculate total transfers for given date range grouped by symbol
# ARG: tframe : timeframe (see Utils::getTimeFrameNames for defs) ytd by def
# RET: scalar

sub getTransfersBySymbol {
    my ($self, %arg) = @_;
    my $tframe = $arg{tframe} || 'ytd';

    croak "Not an object call" unless $self->isa(__PACKAGE__);
    my $range = Stocks::Utils::getDateRange ( $tframe );

    return Stocks::Transaction::getTransfersBySymbol (
                                  portid => $self->id,
                                  sdate  => $range->{sdate}, 
                                  edate  => $range->{edate}, 
                                );
} # getTransfersBySymbol

# Add/edit transaction
# Object method
# Calculate equity,cash,ttlnumber,gain and save tr in DB
# ARG: (id (tr),date,[setl_date],ttype,[ttype_str],symbol,exchange,number,price,[weight],[strike],[fees],[description])
# RET: a newly created transaction

sub addTransaction {
   my($self, %arg) = @_;
   my ($equity, $totalNumber, $prevTotalNumber, $totalEquity) = (0)x5;
   $arg{portid} = $self->id();  # for Transaction.pm

   croak "Not an object call" unless $self->isa(__PACKAGE__);
   croak '"id" is required' unless $self->id;
   croak '"ttype" is required' unless defined $arg{ttype};
   croak '"date" is required' unless defined $arg{date};
   croak '"symbol" is required' unless defined $arg{symbol};
   croak '"price" is required' unless defined $arg{price};
   croak '"number" is required' unless defined $arg{number};
   if ($self->currency eq 'GLD') {
       croak '"weight" is required' unless defined $arg{weight}; 
   }

   if ($arg{ttype} == 7) {
       croak '"setl_date" is required' unless $arg{setl_date};  # setl_date required for options
       croak '"strike" is required' unless $arg{strike};        # strike required for options
   }

   $arg{setl_date} ||= $arg{date};

   Stocks::Utils::trim ( \$arg{symbol} );

   my $tnew = Stocks::Transaction->new( %arg );
   $tnew->id($arg{id}) if $arg{id}; # transaction id; edit mode

   my @tlist = @{$self->getTransactions(symbol => $arg{symbol}, exchange => $arg{exchange}, order => 'asc' )};  # all types
   my $tx;
   my $thistx_unixts = Stocks::Utils::toUnixTS($arg{date});

# go from oldest to newest transaction for this sym up to given date and calculate total number and equity
# @tlist to contain only transactions immediately before and after given date

   while (@tlist) {
      $tx = shift @tlist;
      my $tx_unixts = Stocks::Utils::toUnixTS ($tx->date);

# Compute Total Equity/number of shares for all transactions for this symbol in DB
      if (($tnew->id && $tnew->id == $tx->id) || $tx_unixts ge $thistx_unixts ) {     # edit mode if id is set
#         unshift @tlist, $tx;
         last;
      } else {
         if ($tx->ttype == 1 || $tx->ttype == 5 || $tx->ttype == 7 ) {  # buy/sell/tfr/call/put
            $totalNumber += $tx->number;
            $totalEquity += $tx->equity;
	 }
      }
   }
 
   $prevTotalNumber = $totalNumber;
   $tnew->cash( $self->_computeCash($tnew,$totalNumber,$totalEquity));
 
   if ($tnew->ttype == 1 || $tnew->ttype == 5 || $tnew->ttype == 7) {  # buy/sell/tfr/call/put
      $tnew->equity( $self->_computeEquity($tnew, $totalNumber, $totalEquity)); # unless $tnew->ttype > 6;
      $totalEquity += $tnew->equity;
      $totalNumber += $tnew->number;

      $tnew->ttlnumber($totalNumber);
      my $factor = $tnew->ttype > 6 ? 100 : 1;
      $tnew->avgprice(abs($totalEquity/($totalNumber*$factor))) if $totalNumber;

# totalNumber : $totalNumber
# totalEquity : $totalEquity
# avgprice    : $tnew->avgprice

# call/put opt: reduce/increase equity by cash in/out 
#   } elsif ( $tnew->ttype == 7 || $tnew->ttype == 8) {   
#      $totalEquity -= $tnew->cash;
#      $tnew->equity(0);
#      $tnew->equity(-$tnew->cash);

   } else {
      $tnew->equity(0);
   }

# totalNumber : $totalNumber
# tnew->number : $tnew->number
# tnew->descr : $tnew->descr

# Override description for shorts
   if ($tnew->ttype == 1 && $prevTotalNumber <= 0 ) {
      if ($tnew->number < 0) {
         $tnew->descr('SHRT SELL '.abs($tnew->number).' of '.$tnew->symbol.' @ '.$tnew->price);
      } elsif ($prevTotalNumber < 0 ) { 
         $tnew->descr('SHRT COVER '.abs($tnew->number).' of '.$tnew->symbol.' @ '.$tnew->price);  
      }
   }
 
   $tnew->save;   

# Check & Fix all following transactions' (if any) computed fields
   $self->_updateTr(\@tlist, $totalNumber, $totalEquity); 

   return $tnew;

} # addTransaction


# drops the transaction and fixes up equity on other transactions
# ARG: transaction to delete
# RET: none

sub dropTransaction {
   my ($self,%arg) = @_;
   my $tr = $arg{'tr'};
   
   croak "Not an object call" unless $self->isa(__PACKAGE__);
   return unless ($tr->portid == $self->id);
   
   my @tlist = @{ $self->getTransactions( symbol => $tr->symbol, order => 'asc' ) };
   my ($totalNumber, $totalEquity);

   while (@tlist) {
      my $tx = shift @tlist;
      if ($tx->id == $tr->id) {
         last;
      } else {
         if ($tx->ttype == 1) {  		# buy/sell?
            $totalNumber += $tx->number;
            $totalEquity += $tx->equity;
         }
      }
   }

   $self->_updateTr(\@tlist, $totalNumber, $totalEquity); 

   $tr->delete;
} # dropTransaction

# ARG: \@transactions, totalNumber, totalEquity
# EFFECT: iterates through @transactions and fixes equity, given a base
#         equity of totalEquity on totalNumber of shares

sub _updateTr {
   my ($self,$tlist,$totalNumber,$totalEquity) = @_;
   my @tlist = @{$tlist};
   my ($tx, $equity, @dirty);
   
   croak "Not an object call" unless $self->isa(__PACKAGE__);

# check computed fields in DB against current 
   while (@tlist) {
      $tx = shift @tlist;

      if ($tx->ttype == 1) {
         $equity = $self->_computeEquity($tx,$totalNumber,$totalEquity);
         $totalEquity += $equity;
         $totalNumber += $tx->number;

	 $tx->ttlnumber($totalNumber);
         $tx->avgprice(abs($totalEquity / $totalNumber)) if $totalNumber;
	 $tx->equity($equity);
	 my $id = $tx->save();

      }
   }

} # _updateTr

# Compute the change to the cash position resulting from this transaction
# ARGS: transaction

sub _computeCash {
   my $self = shift;
   my $t = shift;
   my $totalnum = shift;
   my $totaleq = shift;
   my $change = $t->price * $t->number; 
# change : $change
   my $cash;

   croak "Not an object call" unless $self->isa(__PACKAGE__);

   if ($t->ttype == 1) {     # buy/sell 
      $cash = (- $change - $t->fees()) * $t->fx_rate();
      if ($t->number > 0 ) { 			   # buying
         if ($totalnum + $t->number <=0) {  	   # covering short

# totaleq : $totaleq
# cash : $cash
# t->fees : $t->fees
# cover short cash: $totaleq + ($totaleq + $change + $t->fees)

	    return $cash   # Negative
	 } else { return $cash } 		   # buying long
      } elsif ($totalnum + $t->number <0) {	   # selling short

# sell short cash: ($change + $t->fees())

#           return -($change + $t->fees);   # Positive 
           return -($change );   # Positive 
      } else {					   # selling long
           return $cash
      }
   } elsif ($t->ttype == 0 || $t->ttype == 4) {  # cash in/out
      return ($change - $t->fees()) * $t->fx_rate(); 
   } elsif ($t->ttype == 2 || $t->ttype == 3) {  # div /int
      return $t->price
   } elsif ($t->ttype == 6) {  # fee
      return $t->price*-1
   } elsif ($t->ttype == 7) {  # call/put
#!!      if ($totalnum + $t->number <0) {
         return $t->number * $t->price * -100 - $t->fees();
#!!         } else {
#!!	 return 0
#!!      }
   } else {
      return 0
   }

} # _computeCash

# Compute the change in equity resulting from this buy/sell transaction.
# ARGS: transaction, total transactions, total equity
#       where the totals are totals for all preceeding transactions on
#       the same symbol as this transaction
# RETURN: the change in equity
#
sub _computeEquity {
   my ($self,$t,$totalNumber,$totalEquity) = @_;
   my $equity;
   my $number = $t->number();
   my $price = $t->price();
   my $fees = $t->fees();
   my $fx_rate = $t->fx_rate();
   my $ttype = $t->ttype();
   
   croak "Not an object call" unless $self->isa(__PACKAGE__);
   
   $totalNumber ||=0;

   if ($ttype == 7 ) {  # call/put
      $totalNumber *= 100;
      $number *= 100;
   }

   if ($totalNumber >= 0) {
      # we are not short yet
 
      if ($number >= 0) {  # this is buy 
         $equity = ($price * $number + $fees); # * $fx_rate; we don't normally buy stocks in diff currency

      } else {     # this is sell
         if (($number + $totalNumber) >= 0) {  # not short
             # sell $number, since $number < 0 $totalNumber must be > 0
             $equity = $number * $totalEquity/$totalNumber;   #  negative
         } else {  # short 
             # sell $totalNumber, then short sell the rest 
             $equity = ($totalEquity + $price * ($totalNumber + $number) + $t->fees ); #* $fx_rate;  # Negative
         }
      }
   } else {
      # we are already short
 
# short : $number

      if ($number <= 0) {
         # short sell $number
         $equity = ($price * $number + $fees);
          
#         $equity = ($price * $number);

# equity : $equity

      } else {
         # we are filling
         if (($number + $totalNumber) <= 0) {
            # fill $number (note $totalNumber < 0, no div error)
            $equity = ($totalEquity * $number/$totalNumber)   # Positive
         } else {
            # fill -$totalNumber and buy $totalNumber + $number
            # $equity = - $totalEquity * $totalNumber/$totalNumber
            # + $price * ($totalNumber + $number)
            $equity = (-$totalEquity + $price * ($totalNumber + $number) +$t->fees()); # * $fx_rate;
         }
      }
   }
   return $equity;
}

# Get portfolio totals from daily_totals for given date range
# ARG: sdate : start date (opt) def earliest
#      edate : end date (opt)   def latest 
#
sub getTotals {
  my ($self,%arg) = @_;

   croak "Not an object call" unless $self->isa(__PACKAGE__);

  my $sdate = $arg{sdate} || '';
  my $edate = $arg{edate} || '';

  return Stocks::DailyTotals::getPortTotals (portid => $self->id, sdate => $sdate, edate => $edate);

} # getTotals

# Find records matching given criteria
# Class method
# ARGS: field : field to search on
#       type: Str, Int, Num (LIKE queries for Str)
#       value : value for the field
#       order_by : sort field
#       order : sort order (ASC/DESC) (opt) def ASC 
#       returns : type of result returned : 'hash', 'array', 'scalar' 
# RET: hashref/arrayref/scalar
#
sub find {
  my %arg =  @_;
  $arg{table} =  _table();

  _find ( %arg );

} # find

# Is record for this user in a DB?
# ARG: none
# RET: bool

sub found {
  my $self = shift;
  my $where;

  return unless $self->id || ($self->username && $self->name);

  if ( $self->id() ) {
     $where = 'id='.$self->id();
  } else {
     $where = "username='" .$self->username. "' AND name='". $self->name. "'";
  }

  my $id = Stocks::DB::select (table => _table(),
  			       fields => [qw(id)],
			       where => $where,
			       returns => 'scalar'
			      );


 $self->id ($id) if $id;

 return $id;
} # found


#____________________Private Methods____________________


# Insert DB record
# Private object method
# ARGS: none
# EFFECTS: inserts row into DB; 
# RET: id of inserted record
#
sub _insert {
  my $self = shift;
  my $keyval = $self->get_attributes();

  my $id = Stocks::DB::insert (
  			    table => _table(),
  			    keyval => $keyval 
			      );

  croak '_insert error: could not insert record: ', $self->dump() unless $id;

  return $id
} #_insert

# Update DB record
# Private object method
# ARGS: none
# EFFECTS: updates existing DB record
#          sets "errormsg" property in case of failure
# RET:id of the updated record 

sub _update {
  my $self = shift;
  my $id = $self->id;
  my $keyval = $self->get_attributes();
  my $where = 'id='.$self->id;

  croak '_update error: could not update record - "id" was not defined' unless $self->id;

  my $updated_id = Stocks::DB::update (
  				   table => _table(),
  				   keyval => $keyval, 
				   where => $where
				  );
  
  croak '_update error: could not update record: ', $self->dump() unless $updated_id;

  return $updated_id 

}

1;

__END__
 
=head1 NAME
 
Stocks::Portfolio -- Stocks Portfolio Class
 
=head1 SYNOPSIS

Provides Portfolio-related methods 

=head1 INTERFACE

sub _table { 'portfolio' }
sub _trtable { 'transaction' }
sub BUILD {
sub assets {
sub cash {
sub equity {
sub yrgain {
sub TodaysTrades {
sub curvalue {
sub get {
sub assert_ownership {
sub Delete {
sub delete_transactions {
sub getAll {
sub getTrCount {
sub getHTrCount {
sub getOldestTr {
sub getLatestTr {
sub getOldestHTr {
sub getLatestHTr {
sub getCurVal {
sub getPrevVal {
sub getMonth {
sub getMonthTotals {
sub getLastTotals {
sub getPrevTotals {
sub getQtrTotals {
sub getDayTotalDep {
sub getDayTotalTransf {
sub getWeekTotalDep {
sub getMonthTotalDep {
sub getMonthTotalTransf {
sub getLMonthTotalDep {
sub getQtrTotalDep {
sub getLQtrTotalDep {
sub getYrDeposits {
sub getLYrDeposits {
sub getTransactions {
sub getHistory {
sub getSymbols {
sub getHSymbols {
sub getEquity {
sub getAssets {
sub getCurrentValue {
sub getRealGain {
sub getTtlGain {
sub getCash {
sub getTodaysTrades {
sub getAllTodayTrades {
sub getTradesNum {
sub getTrades {
sub getDividends {
sub getFees {
sub getFeesBySymbol {
sub getPosTransfers {
sub getCashTransfers {
sub getTransfersBySymbol {
sub addTransaction {
sub dropTransaction {
sub _updateTr {
sub _computeCash {
sub _computeEquity {
sub getTotals {
sub find {
sub found {
sub _insert {
sub _update {


=head2 constructor

=head2 save
Saves portfolio into table

=head2 delete

deletes portfolio from table

=head1 AUTHOR

Dimitri Ostapenko (d@perlnow.com)
 

=cut
