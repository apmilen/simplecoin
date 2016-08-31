import "ds-whitelist/whitelist.sol";
import "erc20/base.sol";
import "erc20/erc20.sol";
import "feedbase/feedbase.sol";
import "sensible.sol";

contract Simplecoin is ERC20Base(0), DSAuth, Sensible {
    // precision of the price feed
    uint public constant PRICE_UNIT = 10**18;

    address    public  owner;
    Feedbase   public  feedbase;
    bytes32    public  rules;
    Whitelist  public  issuers;
    Whitelist  public  holders;

    CollateralType[] types;

    struct CollateralType {
        ERC20    token;
        uint24   feed;
        address  vault;
        uint     spread;
        uint     debt;
        uint     ceiling;
    }

    function Simplecoin(
        Feedbase   _feedbase,
        bytes32    _rules,
        Whitelist  _issuers,
        Whitelist  _holders
    ) {
        owner    = msg.sender;
        feedbase = _feedbase;
        rules    = _rules;
        issuers  = _issuers;
        holders  = _holders;
    }

    function setOwner(address new_owner) noeth auth {
        owner = new_owner;
    }

    //------------------------------------------------------

    function nextType() constant returns (uint48) {
        return uint48(types.length);
    }

    function register(ERC20 token)
        noeth auth returns (uint48 id)
    {
        return uint48(types.push(CollateralType({
            token:    token,
            vault:    0,
            feed:     0,
            spread:   0,
            debt:     0,
            ceiling:  0,
        })) - 1);
    }

    function setVault(uint48 type_id, address vault) noeth auth {
        types[type_id].vault = vault;
    }

    function setFeed(uint48 type_id, uint24 feed) noeth auth {
        types[type_id].feed = feed;
    }

    function setSpread(uint48 type_id, uint spread) noeth auth {
        types[type_id].spread = spread;
    }

    function setCeiling(uint48 type_id, uint ceiling) noeth auth {
        types[type_id].ceiling = ceiling;
    }

    function unregister(uint48 collateral_type) noeth auth {
        delete types[collateral_type];
    }

    //------------------------------------------------------

    function token(uint48 type_id) constant returns (ERC20) {
       return types[type_id].token;
    }

    function vault(uint48 type_id) constant returns (address) {
       return types[type_id].vault;
    }

    function feed(uint48 type_id) constant returns (uint24) {
       return types[type_id].feed;
    }

    function spread(uint48 type_id) constant returns (uint) {
       return types[type_id].spread;
    }

    function ceiling(uint48 type_id) constant returns (uint) {
       return types[type_id].ceiling;
    }

    function debt(uint48 type_id) constant returns (uint) {
       return types[type_id].debt;
    }

    //------------------------------------------------------

    modifier auth_holder(address who) {
        assert(holders.isWhitelisted(who));
        _
    }

    function transfer(address to, uint amount)
        auth_holder(msg.sender) auth_holder(to) returns (bool)
    {
        return super.transfer(to, amount);
    }

    function transferFrom(address from, address to, uint amount)
        auth_holder(from) auth_holder(to) returns (bool)
    {
        return super.transferFrom(from, to, amount);
    }

    //------------------------------------------------------

    modifier auth_issuer() {
        assert(issuers.isWhitelisted(msg.sender));
        _
    }

    function issue(uint48 collateral_type, uint pay_how_much)
        auth_issuer noeth synchronized returns (uint issued_quantity)
    {
        var t = types[collateral_type];
        assert(t.token != address(0));  // deleted

        assert(t.token.transferFrom(msg.sender, t.vault, pay_how_much));

        var price = getPrice(t.feed);
        var mark_price = price + price / t.spread;
        assert(safeToMul(PRICE_UNIT, pay_how_much));
        issued_quantity = (PRICE_UNIT * pay_how_much) / mark_price;

        assert(safeToAdd(_balances[msg.sender], issued_quantity));
        _balances[msg.sender] += issued_quantity;

        assert(safeToAdd(_supply, issued_quantity));
        _supply += issued_quantity;

        assert(safeToAdd(t.debt, issued_quantity));
        t.debt += issued_quantity;

        assert(t.debt <= t.ceiling);
        assert(_balances[msg.sender] <= _supply);
    }

    function cover(uint48 collateral_type, uint stablecoin_quantity)
        auth_issuer noeth synchronized returns (uint returned_amount)
    {
        var t = types[collateral_type];
        assert(t.token != address(0));  // deleted

        assert(safeToSub(_balances[msg.sender], stablecoin_quantity));
        _balances[msg.sender] -= stablecoin_quantity;

        assert(safeToSub(_supply, stablecoin_quantity));
        _supply -= stablecoin_quantity;

        assert(safeToSub(t.debt, stablecoin_quantity));
        t.debt -= stablecoin_quantity;

        var price = getPrice(t.feed);
        var mark_price = price - price / t.spread;
        assert(safeToMul(stablecoin_quantity, mark_price));
        returned_amount = (stablecoin_quantity * mark_price) / PRICE_UNIT;

        assert(t.token.transferFrom(t.vault, msg.sender, returned_amount));

        assert(t.debt <= t.ceiling);
        assert(_balances[msg.sender] <= _supply);
    }

    function getPrice(uint24 feed) internal returns (uint) {
        var (price, ok) = feedbase.get(feed);
        assert(ok);
        return uint(price);
    }
}