import BTree "mo:stableheapbtreemap/BTree";
import Option "mo:base/Option";
import Debug "mo:base/Debug";
import Nat "mo:base/Nat";
import Float "mo:base/Float";
import Ledger "./icrc_ledger";
import Principal "mo:base/Principal";
import Vector "mo:vector";
import Timer "mo:base/Timer";
import Array "mo:base/Array";
import Error "mo:base/Error";
import Blob "mo:base/Blob";
import Nat64 "mo:base/Nat64";
import Nat32 "mo:base/Nat32";
import Time "mo:base/Time";
import Int "mo:base/Int";
import Prim "mo:⛔";
import Nat8 "mo:base/Nat8";

module {

    let RETRY_EVERY_SEC:Float = 60;

    type TransactionInput = {
        amount: Nat;
        to: Ledger.Account;
        from_subaccount : ?Blob;
    };

    type Transaction = {
        amount: Nat;
        to : Ledger.Account;
        from_subaccount : ?Blob;
        var created_at_time : Nat64; // 1000000000
        memo : Blob;
        var tries: Nat;
    };

    public type Mem = {
        transactions : BTree.BTree<Nat64, Transaction>;
        var started : Bool;
        var stored_owner : ?Principal;
    };

    public func Mem() : Mem {
        return {
            transactions = BTree.init<Nat64, Transaction>(?16);
            var started = false;
            var stored_owner = null;
        };
    };

    public class Sender({
        mem : Mem;
        ledger_id: Principal;
        onError: (Text) -> ();
        onConfirmations : ([Nat64]) -> ();
        onCycleEnd : (Nat64) -> (); // Measure performance of following and processing transactions. Returns instruction count
    }) {

        let ledger = actor(Principal.toText(ledger_id)) : Ledger.Oneway;
        let ledger_cb = actor(Principal.toText(ledger_id)) : Ledger.Self;

        var stored_fee:?Nat = null;

        private func cycle() : async () {
            let ?owner = mem.stored_owner else return;
            if (not mem.started) return;
            let inst_start = Prim.performanceCounter(1); // 1 is preserving with async

            if (Option.isNull(stored_fee)) {
                stored_fee := ?(await ledger_cb.icrc1_fee());
            };
            let ?fee = stored_fee else Debug.trap("Fee not available");

            let now = Int.abs(Time.now());
  
            let transactions_to_send = BTree.scanLimit<Nat64, Transaction>(mem.transactions, Nat64.compare, 0, ^0, #fwd, 500);

            label vtransactions for ((id, tx) in transactions_to_send.results.vals()) {
                
                    // Retry every 30 seconds
                    let time_for_try = Float.toInt(Float.ceil((Float.fromInt(now - Nat64.toNat(tx.created_at_time)))/RETRY_EVERY_SEC));

                    if (tx.tries >= time_for_try) continue vtransactions;
                    tx.tries += 1;
    
                    try {
                        // Relies on transaction deduplication https://github.com/dfinity/ICRC-1/blob/main/standards/ICRC-1/README.md
                        ledger.icrc1_transfer({
                            amount = tx.amount - fee;
                            to = tx.to;
                            from_subaccount = tx.from_subaccount;
                            created_at_time = ?tx.created_at_time;
                            memo = ?tx.memo;
                            fee = ?fee;
                        });
                    } catch (e) { 
                        onError("sender:" # Error.message(e));
                    };
            };
    
            ignore Timer.setTimer(#seconds 5, cycle);
            let inst_end = Prim.performanceCounter(1);
            onCycleEnd(inst_end - inst_start);
        };

        public func confirm(txs: [Ledger.Transaction]) {
            let ?owner = mem.stored_owner else return;

            let confirmations = Vector.new<Nat64>();
            label tloop for (tx in txs.vals()) {
                let ?tr = tx.transfer else continue tloop;
                if (tr.from.owner != owner) continue tloop;
                let ?memo = tr.memo else continue tloop;
                let ?id = DNat64(Blob.toArray(memo)) else continue tloop;
                
                ignore BTree.delete<Nat64, Transaction>(mem.transactions, Nat64.compare, id);
                Vector.add<Nat64>(confirmations, id);
            };
            onConfirmations(Vector.toArray(confirmations));
        };

        public func get_fee() :  Nat {
            let ?fee = stored_fee else Debug.trap("Fee not available");
            return fee;
        };

        public func send(id:Nat64, tx: TransactionInput) {
            let txr : Transaction = {
                amount = tx.amount;
                to = tx.to;
                from_subaccount = tx.from_subaccount;
                var created_at_time = Nat64.fromNat(Int.abs(Time.now()));
                memo = Blob.fromArray(ENat64(id));
                var tries = 0;
            };
            
            ignore BTree.insert<Nat64, Transaction>(mem.transactions, Nat64.compare, id, txr);
        };

        public func start(owner:Principal) {
            mem.stored_owner := ?owner;
            mem.started := true;
            ignore Timer.setTimer(#seconds 2, cycle);
        };

        public func stop() {
            mem.started := false;
        };

        public func ENat64(value : Nat64) : [Nat8] {
            return [
                Nat8.fromNat(Nat64.toNat(value >> 56)),
                Nat8.fromNat(Nat64.toNat((value >> 48) & 255)),
                Nat8.fromNat(Nat64.toNat((value >> 40) & 255)),
                Nat8.fromNat(Nat64.toNat((value >> 32) & 255)),
                Nat8.fromNat(Nat64.toNat((value >> 24) & 255)),
                Nat8.fromNat(Nat64.toNat((value >> 16) & 255)),
                Nat8.fromNat(Nat64.toNat((value >> 8) & 255)),
                Nat8.fromNat(Nat64.toNat(value & 255)),
            ];
        };

        public func DNat64(array : [Nat8]) : ?Nat64 {
            if (array.size() != 8) return null;
            return ?(Nat64.fromNat(Nat8.toNat(array[0])) << 56 | Nat64.fromNat(Nat8.toNat(array[1])) << 48 | Nat64.fromNat(Nat8.toNat(array[2])) << 40 | Nat64.fromNat(Nat8.toNat(array[3])) << 32 | Nat64.fromNat(Nat8.toNat(array[4])) << 24 | Nat64.fromNat(Nat8.toNat(array[5])) << 16 | Nat64.fromNat(Nat8.toNat(array[6])) << 8 | Nat64.fromNat(Nat8.toNat(array[7])));
        };
    };

};
