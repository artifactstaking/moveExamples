module guess_game::game {
    use std::vector;
 
    use sui::bcs;
    use sui::hash;
    use sui::transfer;
    use sui::coin::{Self, Coin};
    use sui::object::{Self, UID};
    use sui::clock::{Self, Clock};
    use sui::balance::{Self, Balance};
    use sui::tx_context::{Self, TxContext};

    struct Game<phantom C> has key {
        id: UID,
        balance: Balance<C>,
        players: vector<Player>
    }

    struct Player has store {
        guess: u64,
        address: address
    }

    const EMaxPlayersReached: u64 = 0;
    const EInvalidStakeAmount: u64 = 1;

    public fun create<C>(
        ctx: &mut TxContext
    ): Game<C> {
        Game {
            id: object::new(ctx),
            balance: balance::zero(),
            players: vector::empty(),
        }
    }

    public fun create_and_play<C>(
        guess: u64,
        stake: Coin<C>,
        ctx: &mut TxContext
    ): Game<C> {
        let game = create<C>(ctx);
        play(&mut game, guess, stake, ctx);

        game
    }

    public fun return_and_share<C>(
        self: Game<C>
    ) {
        transfer::share_object(self)
    }

    public fun play<C>(
        self: &mut Game<C>,
        guess: u64,
        stake: Coin<C>,
        ctx: &mut TxContext
    ) {
        assert!(vector::length(&self.players) < 2, EMaxPlayersReached);

        let balance = balance::value(&self.balance);
        if(balance != 0u64) { assert!(coin::value(&stake) == balance, EInvalidStakeAmount) };

        let player = Player { 
            guess,
            address: tx_context::sender(ctx)
        };

        coin::put(&mut self.balance, stake);
        vector::push_back(&mut self.players, player);
    }

    public fun random_number<C>(
        game: &Game<C>,
        clock: &Clock,
        ctx: &mut TxContext
    ): u64 {
        let uid = object::new(ctx);
        let seed = object::uid_to_bytes(&uid);
        object::delete(uid);

        let player_1 = vector::borrow(&game.players, 0);
        let player_2 = vector::borrow(&game.players, 1);

        let (min, max) = if(player_1.guess > player_2.guess) { 
            (player_2.guess, player_1.guess) 
        } else { 
            (player_1.guess, player_2.guess) 
        };

        vector::append(&mut seed, bcs::to_bytes(&player_1.address));
        vector::append(&mut seed, bcs::to_bytes(&player_2.address));
        vector::append(&mut seed, bcs::to_bytes(&clock::timestamp_ms(clock)));

        let bcs = bcs::new(hash::keccak256(&seed));
        let value = bcs::peel_u64(&mut bcs);
        value % (max - min) + min
    }
}