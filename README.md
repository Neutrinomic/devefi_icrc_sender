# devefi-icrc-sender

## Install
```
mops add devefi-icrc-sender
```

## Usage

Better example here: https://github.com/Neutrinomic/devefi_backpass

```motoko
import IcrcSender "mo:devefi-icrc-sender";


    // Reader

    stable let icrc_reader_mem = IcrcReader.Mem();

    let icrc_reader = IcrcReader.Reader({
        mem = icrc_reader_mem;
        ledger_id;
        start_from_block = #last;
        onError = func (e: Text) = Vector.add(errors, e); // In case a cycle throws an error
        onCycleEnd = func (instructions: Nat64) {}; // returns the instructions the cycle used. 
                                                    // It can include multiple calls to onRead
        onRead = func (transactions: [IcrcReader.Transaction]) {
            icrc_sender.confirm(transactions);
            // do something here
            // basically the main logic of the vector
            // we are going to send tokens back to the sender
            let fee = icrc_sender.get_fee();
            let ?me = actor_principal else return;
            label txloop for (tx in transactions.vals()) {
                let ?tr = tx.transfer else continue txloop;
                if (tr.to.owner == me) {
                    if (tr.amount <= fee) continue txloop; // ignore it
                    icrc_sender.send(next_tx_id, {
                        to = tr.from;
                        amount = tr.amount;
                        from_subaccount = tr.to.subaccount;
                    });
                    next_tx_id += 1;
                }
            }
        };
    });


```
