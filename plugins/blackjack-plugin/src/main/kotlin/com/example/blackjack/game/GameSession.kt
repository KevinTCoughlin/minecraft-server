package com.example.blackjack.game

import java.util.UUID

/** The current state of a Blackjack game. */
enum class GameState {
    PLAYER_TURN,
    DEALER_TURN,
    FINISHED
}

/** Possible outcomes of a Blackjack game. */
enum class GameResult {
    PLAYER_WIN,
    DEALER_WIN,
    /** A tie (push). */
    PUSH,
    PLAYER_BLACKJACK,
    PLAYER_BUST,
    DEALER_BUST
}

/**
 * Represents an active Blackjack game session for a player.
 *
 * @property playerId The unique ID of the player.
 */
class GameSession(val playerId: UUID) {

    val deck = Deck()
    val playerHand = Hand()
    val dealerHand = Hand()

    var state: GameState = GameState.PLAYER_TURN
        private set

    var result: GameResult? = null
        private set

    /** Returns `true` if the game has finished. */
    val isFinished: Boolean get() = state == GameState.FINISHED

    /** Returns `true` if it's currently the player's turn. */
    val isPlayerTurn: Boolean get() = state == GameState.PLAYER_TURN

    init {
        startNewGame()
    }

    private fun startNewGame() {
        deck.reset()
        playerHand.clear()
        dealerHand.clear()
        state = GameState.PLAYER_TURN
        result = null

        // Deal initial cards: player, dealer, player, dealer
        repeat(2) {
            playerHand += deck.draw()
            dealerHand += deck.draw()
        }

        // Check for player blackjack
        if (playerHand.isBlackjack) {
            playDealerTurn()
        }
    }

    /**
     * Player takes a hit (draws another card).
     *
     * @return `true` if the action was valid, `false` if not player's turn.
     */
    fun hit(): Boolean {
        if (!isPlayerTurn) return false

        playerHand += deck.draw()

        if (playerHand.isBust) {
            state = GameState.FINISHED
            result = GameResult.PLAYER_BUST
        }

        return true
    }

    /**
     * Player stands (ends their turn).
     *
     * @return `true` if the action was valid, `false` if not player's turn.
     */
    fun stand(): Boolean {
        if (!isPlayerTurn) return false
        playDealerTurn()
        return true
    }

    private fun playDealerTurn() {
        state = GameState.DEALER_TURN

        // Dealer draws until 17 or higher
        while (dealerHand.value < 17) {
            dealerHand += deck.draw()
        }

        state = GameState.FINISHED
        determineWinner()
    }

    private fun determineWinner() {
        result = when {
            playerHand.isBlackjack && dealerHand.isBlackjack -> GameResult.PUSH
            playerHand.isBlackjack -> GameResult.PLAYER_BLACKJACK
            dealerHand.isBlackjack -> GameResult.DEALER_WIN
            playerHand.isBust -> GameResult.PLAYER_BUST
            dealerHand.isBust -> GameResult.DEALER_BUST
            playerHand.value > dealerHand.value -> GameResult.PLAYER_WIN
            dealerHand.value > playerHand.value -> GameResult.DEALER_WIN
            else -> GameResult.PUSH
        }
    }
}
