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
        is_finished: bool,
        balance: Balance<C>,
        players: vector<Player>
    }

    struct Player has store {
        guess: u64,
        address: address
    }

    const EGameAlreadyFinished: u64 = 1;
    const EPlayerAlreadyPlayed: u64 = 2;
    const EInvalidGuess: u64 = 3;
    const EInvalidBetAmount: u64 = 4;

    public entry fun create_game<C>(
        ctx: &mut TxContext
    ) {
        transfer::share_object(create_game_internal<C>(ctx));
    }

    public entry fun create_and_play_game<C>(
        guess: u64,
        payment: Coin<C>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let game = create_game_internal<C>(ctx);
        play_game(&mut game, guess, payment, clock, ctx);

        transfer::share_object(game)
    }

    public entry fun play_game<C>(
        self: &mut Game<C>,
        guess: u64,
        payment: Coin<C>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        assert!(!self.is_finished, EGameAlreadyFinished);

        let sender = tx_context::sender(ctx);
        if(!vector::is_empty(&self.players)) {
            let balance = balance::value(&self.balance);
            let player_1 = vector::borrow(&self.players, 0);
            
            assert!(player_1.guess != guess, EInvalidGuess);
            assert!(player_1.address != sender, EPlayerAlreadyPlayed);
            assert!(coin::value(&payment) == balance, EInvalidBetAmount);
        } else {
            assert!(coin::value(&payment) != 0, EInvalidBetAmount);
        };

        coin::put(&mut self.balance, payment);
        vector::push_back(&mut self.players, Player { guess, address: sender });

        if(vector::length(&self.players) == 2) { 
            finish_game(self, clock, ctx) 
        }
    }

    fun create_game_internal<C>(
        ctx: &mut TxContext
    ): Game<C> {
        Game {
            id: object::new(ctx),
            is_finished: false,
            balance: balance::zero(),
            players: vector::empty(),
        }
    }

    fun finish_game<C>(
        self: &mut Game<C>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let rand = random_number(self, clock, ctx);
        let player_1 = vector::borrow(&self.players, 0);
        let player_2 = vector::borrow(&self.players, 1);

        let diff_1 = if(player_1.guess < rand) { rand - player_1.guess } else { player_1.guess - rand };
        let diff_2 = if(player_2.guess < rand) { rand - player_2.guess } else { player_2.guess - rand };

        let total_balance = balance::withdraw_all(&mut self.balance);

        if(diff_1 < diff_2) {
            transfer::public_transfer(coin::from_balance(total_balance, ctx), player_1.address)
        } else if(diff_2 < diff_1) {
            transfer::public_transfer(coin::from_balance(total_balance, ctx), player_2.address)
        } else {
            let half_balance = balance::value(&total_balance) / 2;

            transfer::public_transfer(coin::take(&mut total_balance, half_balance, ctx), player_1.address);
            transfer::public_transfer(coin::from_balance(total_balance, ctx), player_2.address)
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