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
        amount: Balance<C>,
        players: vector<Player>,
        is_finished: bool
    }

    struct Player has store {
        guess: u64,
        address: address
    }

    const EMaxPlayersReached: u64 = 0;
    const EInvalidBetAmount: u64 = 1;

    public fun create<C>(
        ctx: &mut TxContext
    ): Game<C> {
        Game {
            id: object::new(ctx),
            amount: balance::zero(),
            players: vector::empty(),
            is_finished: false
        }
    }

    public fun create_and_play<C>(
        guess: u64,
        payment: Coin<C>,
        clock: &Clock,
        ctx: &mut TxContext
    ): Game<C> {
        let game = create<C>(ctx);
        play(&mut game, guess, payment, clock, ctx);

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
        payment: Coin<C>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        assert!(vector::length(&self.players) < 2, EMaxPlayersReached);

        let bet_amount = balance::value(&self.amount);
        if(bet_amount != 0u64) { assert!(coin::value(&payment) == bet_amount, EInvalidBetAmount) };

        let player = Player { 
            guess,
            address: tx_context::sender(ctx)
        };

        coin::put(&mut self.amount, payment);
        vector::push_back(&mut self.players, player);

        if(vector::length(&self.players) == 2) { 
            finish_game(self, clock, ctx) 
        }
    }

    fun finish_game<C>(
        self: &mut Game<C>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let number = random_number(self, clock, ctx);

        let player_1 = vector::borrow(&self.players, 0);
        let player_2 = vector::borrow(&self.players, 1);

        let diff_1 = if(player_1.guess < number) { number - player_1.guess } else { player_1.guess - number };
        let diff_2 = if(player_2.guess < number) { number - player_2.guess } else { player_2.guess - number };

        let funds = balance::withdraw_all(&mut self.amount);

        if(diff_1 < diff_2) {
            transfer::public_transfer(coin::from_balance(funds, ctx), player_1.address)
        } else if(diff_2 < diff_1) {
            transfer::public_transfer(coin::from_balance(funds, ctx), player_2.address)
        } else {
            let half = balance::value(&funds) / 2;

            transfer::public_transfer(coin::take(&mut funds, half, ctx), player_2.address);
            transfer::public_transfer(coin::from_balance(funds, ctx), player_2.address)
        };

        self.is_finished = true
    }

    fun random_number<C>(
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