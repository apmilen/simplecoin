pragma solidity ^0.4.4;

import "dapple/script.sol";
import "feedbase/feedbase.sol";

contract CallSimplecoinFactory is Script {
  function CallSimplecoinFactory () {
    var factory = env.factory;
    exportObject("simplecoin", factory.create(Feedbase200(0x202b13e54d35f29296fa5a549f5e3e5b10865928), "zandycoin", "ZND"));
  }
}