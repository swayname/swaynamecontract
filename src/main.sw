contract;

abi StoreString {
    #[storage(read)]
    fn get_name(identity: Identity) -> Option<String>;

    #[storage(read)]
    fn get_baseprice() -> u64;

    #[storage(read)]
    fn get_basepercent() -> u64;

    #[storage(read)]
    fn get_record(name_str: str) -> Option<Record>;
    #[storage(read)]
    fn get_market(name_str: str) -> Option<Market>;
    
    #[payable, storage(read, write)]
    fn register(name_str: str, _year: u64);

    //extend name
    #[payable, storage(read, write)]
    fn extend(name_str: str, _year: u64);

    #[storage(read, write)]
    fn tranfer(name_str: str, recev: Identity);

    //set main name
    #[storage(read, write)]
    fn resolving(name_str: str);

    #[storage(read, write)]
    fn list(name_str: str, _price: u64);

    #[storage(read, write)]
    fn delist(name_str: str);

    #[payable, storage(read, write)]
    fn buy(name_str: str);

    #[storage(read, write)]
    fn claim(_amount: u64);

    #[storage(read, write)]
    fn set_baseprice(_price: u64);

    #[storage(read, write)]
    fn set_basepercent(_percent: u64);
}

use std::{
    auth::msg_sender,
    block::timestamp,
    call_frames::msg_asset_id,
    constants::ZERO_B256,
    context::msg_amount,
    hash::{
        Hash,
        sha256,
    },
    storage::{
        storage_bytes::*,
        storage_string::*,
        storage_vec::*,
    },
    asset::*,
    string::String,
};
use std::bytes::Bytes;
use std::logging::log;


configurable {
    ADMIN: Identity = Identity::Address(Address::from(0xf76c923935245f05df9de78ff8fa97739b6537ae5b54a8cc8c7829cb8bdfc8f6)),
}

enum AuthorizationError {
    /// Emitted when the caller is not the owner of a record or the registry.
    SenderNotOwner: (),
    NameAlreadySolved: (),
    NameExpired: (),
}

enum RegistrationValidityError {
    // NameExpired: (),
    NameNotRegistered: (),
    /// Emitted when attempting to register a name that has not expired.
    NameNotExpired: (),
    /// Emitted when the name length is less than 3 bytes.
    NameTooShort: (),
}

enum MarketError {
    NameNotlisted: (),
}

enum AssetError {
    /// Emitted when the amount of asset sent is less than the fee.
    InsufficientPayment: (),
    /// Emitted when an incorrect asset is sent for payment.
    IncorrectAssetSent: (),
}

struct Record {
    expiry: u64,
    identity: Identity,
}

struct Market{
    owner: Identity,
    price: u64,
}

struct NameRegisteredEvent {
    starttime: u64,
    expiry: u64,
    name: String,
    identity: Identity,
}

struct NameExtendEvent {
    addtime: u64,
    name: String,
    identity: Identity,
}

struct NameTransferEvent {
    name: String,
    from: Identity,
    to: Identity,
}

struct ResolvingEvent {
    name: String,
    identity: Identity,
}

struct ListEvent {
    name: String,
    owner: Identity,
    price: u64,
}

struct DelistEvent {
    name: String,
    identity: Identity,
}

struct BuyEvent {
    time: u64,
    price: u64,
    name: String,
    buyer: Identity,
    seller: Identity,
}

storage {
    baseprice: u64 = 100000,
    basepercent: u64 = 995,
    names: StorageMap<b256, Record> = StorageMap {},
    my_names: StorageMap<Identity, StorageString> = StorageMap {},
    markets: StorageMap<b256, Market> = StorageMap {},
}


impl StoreString for Contract {
    #[storage(read)]
    fn get_name(identity: Identity) -> Option<String> {
        //if name is expiried, should return none
        let myname = storage.my_names.get(identity).read_slice();
        if myname.is_some() {
            let name_hash = sha256(myname.unwrap());
            let record = storage.names.get(name_hash).try_read().unwrap();
            //need to check owner of the name, if expiry and bought by another one, should return none
            if timestamp() <= record.expiry && msg_sender().unwrap() == record.identity {
               Some(myname.unwrap())
            }else{
               None
            }
        }else{
               None
        }
    }

    #[storage(read)]
    fn get_baseprice() -> u64{
        storage.baseprice.read()
    }

    #[storage(read)]
    fn get_basepercent() -> u64{
        storage.basepercent.read()
    }

    #[storage(read)]
    fn get_record(name_str: str) -> Option<Record> {
        let name_hash = sha256(String::from_ascii_str(name_str));
        storage.names.get(name_hash).try_read()
    }

    #[storage(read)]
    fn get_market(name_str: str) -> Option<Market>{
        let name_hash = sha256(String::from_ascii_str(name_str));
        storage.markets.get(name_hash).try_read()
    }

    #[payable]
    #[storage(read, write)]
    fn register(name_str: str, _year: u64){
        let my_string = String::from_ascii_str(name_str);
        require(
            my_string.as_bytes().len() >= 2,
            RegistrationValidityError::NameTooShort,
        );

        let total_price = compute_price(my_string.as_bytes(), storage.baseprice.read());
        
        let suffix = String::from_ascii_str(".sway");
        
        let mut result = Bytes::new();
        push_bytes(result, my_string.as_bytes());
        push_bytes(result, suffix.as_bytes());
        
        let name_hash = sha256(String::from_ascii(result));
        let record = storage.names.get(name_hash).try_read();
        if record.is_some() {
            require(timestamp() > record.unwrap().expiry,
                RegistrationValidityError::NameNotExpired,
            );
        }

        // Verify payment
        require(AssetId::base() == msg_asset_id(), AssetError::IncorrectAssetSent);
        require(
            total_price*_year <= msg_amount(),
            AssetError::InsufficientPayment,
        );

        // Store record
        let record = Record{expiry: timestamp() +_year*3600*365*24, identity: msg_sender().unwrap()};
        storage.names.insert(name_hash, record);

        log(NameRegisteredEvent {
            starttime: timestamp(),
            expiry: record.expiry,
            name: String::from_ascii(result),
            identity: msg_sender().unwrap(),
        });
        
    }

    #[payable]
    #[storage(read, write)]
    fn extend(name_str: str, _year: u64){
        let name_hash = sha256(String::from_ascii_str(name_str));
        let record = storage.names.get(name_hash).try_read();
        require(
            record.is_some(),
            RegistrationValidityError::NameNotRegistered,
        );

        require(
            msg_sender().unwrap() == record.unwrap().identity, 
            AuthorizationError::SenderNotOwner,
        );

        let total_price = compute_price_suffix(String::from_ascii_str(name_str).as_bytes(), storage.baseprice.read());

        // Verify payment
        require(AssetId::base() == msg_asset_id(), AssetError::IncorrectAssetSent);
        require(
            total_price*_year <= msg_amount(),
            AssetError::InsufficientPayment,
        );

        // Update stored record
        let mut record = record.unwrap();
        record.expiry = record.expiry + _year*3600*24*365;
        storage.names.insert(name_hash, record);

        log(NameExtendEvent {
            addtime: _year,
            name: String::from_ascii_str(name_str),
            identity: msg_sender().unwrap(),
        });

    }

    #[storage(read, write)]
    fn tranfer(name_str: str, recev: Identity){
        let name_hash = sha256(String::from_ascii_str(name_str));
        let record = storage.names.get(name_hash).try_read();
        require(
            record.is_some(),
            RegistrationValidityError::NameNotRegistered,
        );

        require(
            msg_sender().unwrap() == record.unwrap().identity, 
            AuthorizationError::SenderNotOwner,
        );

        //if name is expiried, cannot transfer
        require(
            timestamp() <= record.unwrap().expiry, 
            AuthorizationError::NameExpired,
        );

        //check msg_sender resolving name not that name
        let mynames = storage.my_names.get(msg_sender().unwrap()).read_slice();
        if mynames.is_some() {
            require(
                mynames.unwrap() != String::from_ascii_str(name_str), 
                AuthorizationError::NameAlreadySolved,
            );
        }

        // Update stored record
        let mut record = record.unwrap();
        record.identity = recev;
        storage.names.insert(name_hash, record);

        log(NameTransferEvent {
            name: String::from_ascii_str(name_str),
            from: msg_sender().unwrap(),
            to: recev,
        });
        
    }

    #[storage(read, write)]
    fn resolving(name_str: str){//set resolving name

        let name_hash = sha256(String::from_ascii_str(name_str));
        let record = storage.names.get(name_hash).try_read();

        require(
            record.is_some(),
            RegistrationValidityError::NameNotRegistered,
        );

        //should check name not expiried  
        require(
            timestamp() <= record.unwrap().expiry, 
            AuthorizationError::NameExpired,
        );
        
        require(
            msg_sender().unwrap() == record.unwrap().identity, 
            AuthorizationError::SenderNotOwner,
        );

        storage.my_names.insert(msg_sender().unwrap(), StorageString{});
        storage.my_names.get(msg_sender().unwrap()).write_slice(String::from_ascii_str(name_str));

        log(ResolvingEvent {
            name: String::from_ascii_str(name_str),
            identity: msg_sender().unwrap(),
        });
        
    }

    #[storage(read, write)]
    fn list(name_str: str, _price: u64){
        let name_hash = sha256(String::from_ascii_str(name_str));
        let record = storage.names.get(name_hash).try_read();

        require(
            record.is_some(),
            RegistrationValidityError::NameNotRegistered,
        );
        require(
            msg_sender().unwrap() == record.unwrap().identity, 
            AuthorizationError::SenderNotOwner,
        );
        require(
            timestamp() <= record.unwrap().expiry, 
            AuthorizationError::NameExpired,
        );

        //check msg_sender resolving name not that name
        let mynames = storage.my_names.get(msg_sender().unwrap()).read_slice();
        if mynames.is_some() {
            require(
                mynames.unwrap() != String::from_ascii_str(name_str), 
                AuthorizationError::NameAlreadySolved,
            );
        }

        let market = Market{owner: msg_sender().unwrap(), price: _price};
        storage.markets.insert(name_hash, market);

        // Update stored record
        let mut record = record.unwrap();
        record.identity = Identity::Address(Address::zero());
        storage.names.insert(name_hash, record);

        log(ListEvent {
            name: String::from_ascii_str(name_str),
            owner: msg_sender().unwrap(),
            price: _price,
        });
    }

    #[storage(read, write)]
    fn delist(name_str: str){
        let name_hash = sha256(String::from_ascii_str(name_str));
        let market = storage.markets.get(name_hash).try_read();
        let record = storage.names.get(name_hash).try_read();

        require(
            market.is_some(),
            MarketError::NameNotlisted,
        );
        require(
            record.is_some(),
            RegistrationValidityError::NameNotRegistered,
        );
        require(
            msg_sender().unwrap() == market.unwrap().owner, 
            AuthorizationError::SenderNotOwner,
        );

        let _market = Market{owner: Identity::Address(Address::zero()), price: 0};
        storage.markets.insert(name_hash, _market);
        // storage.markets.delete(name_hash);

        let mut record = record.unwrap();
        record.identity = msg_sender().unwrap();
        storage.names.insert(name_hash, record);

        log(DelistEvent {
            name: String::from_ascii_str(name_str),
            identity: msg_sender().unwrap(),
        });
    }

    #[payable]
    #[storage(read, write)]
    fn buy(name_str: str){
        let name_hash = sha256(String::from_ascii_str(name_str));
        let market = storage.markets.get(name_hash).try_read();
        let record = storage.names.get(name_hash).try_read();

        require(
            market.is_some(),
            MarketError::NameNotlisted,
        );
        require(
            record.is_some(),
            RegistrationValidityError::NameNotRegistered,
        );
        
        //pay to market.owner
        // Verify payment
        require(AssetId::base() == msg_asset_id(), AssetError::IncorrectAssetSent);
        require(
            market.unwrap().price <= msg_amount(),
            AssetError::InsufficientPayment,
        );

        transfer(market.unwrap().owner, AssetId::base(), market.unwrap().price * storage.basepercent.read()/1000);

        let _market = Market{owner: Identity::Address(Address::zero()), price: 0};
        storage.markets.insert(name_hash, _market);
        // storage.markets.delete(name_hash);

        let mut record = record.unwrap();
        record.identity = msg_sender().unwrap();
        storage.names.insert(name_hash, record);

        log(BuyEvent {
            time: timestamp(),
            price: market.unwrap().price,
            name: String::from_ascii_str(name_str),
            seller: market.unwrap().owner,
            buyer: msg_sender().unwrap(),
        });
    }

    #[storage(read, write)]
    fn claim(_amount: u64){
        require(
            msg_sender().unwrap() == ADMIN, 
            AuthorizationError::SenderNotOwner,
        );
        transfer(msg_sender().unwrap(), AssetId::base(), _amount);
    }

    #[storage(read, write)]
    fn set_baseprice(_price: u64){
         require(
            msg_sender().unwrap() == ADMIN, 
            AuthorizationError::SenderNotOwner,
        );
        storage.baseprice.write(_price);
    }

    #[storage(read, write)]
    fn set_basepercent(_percent: u64){
         require(
            msg_sender().unwrap() == ADMIN, 
            AuthorizationError::SenderNotOwner,
        );
        storage.basepercent.write(_percent);
    }


}

fn push_bytes(ref mut a: Bytes, b: Bytes) {
        let mut i = 0;
        while i < b.len() {
            a.push(b.get(i).unwrap());
            i = i + 1;
        }
}

fn compute_price(a: Bytes, _price: u64) -> u64{
    let len_num = a.len();
    if len_num >= 6 {
        _price
    }else if len_num == 5 {
        _price*2
    }else if len_num == 4 {
        _price*3
    }else if len_num == 3 {
        _price*4
    }else{
        _price*5
    }
}

fn compute_price_suffix(a: Bytes, _price: u64) -> u64{
    let len_num = a.len() - 5;
    if len_num >= 6 {
        _price
    }else if len_num == 5 {
        _price*2
    }else if len_num == 4 {
        _price*3
    }else if len_num == 3 {
        _price*4
    }else{
        _price*5
    }
}
