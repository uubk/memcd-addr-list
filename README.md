# Spamassassin-Plugin-MemcdAddrList
This plugin allows you to store Spamassassins TxRep data in memcached.
Idea & code were heavily inspired by [RedisAWL](https://github.com/benningm/Mail-SpamAssassin-Plugin-RedisAWL).

## Usage
Install the plugin and put the following snippet somewhere in your `local.cf`:
```
txrep_factory Mail::SpamAssassin::MemcdAddrList
header          TXREP eval:check_senders_reputation()
describe        TXREP TxRep score normalizing
priority        TXREP 900
```
TxRep data will now be stored at `localhost:11211`.
