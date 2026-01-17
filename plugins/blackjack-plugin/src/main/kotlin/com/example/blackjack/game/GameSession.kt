package com.example.blackjack.game

import java.util.UUID

enum class GameState {
    PLAYER_TURN,
    DEALER_TURN,
    FINISHED
}

enum class GameResult {
    PLAYER_WIN,
    DEALER_WIN,
    PUSH,  // Tie
    PLAYER_BLACKJACK,
    PLAYER_BUST,
    DEALER_BUST
}

class GameSession(val playerId: UUID) {
    val deck = Deck()
    val playerHand = Hand()
    val dealerHand = Hand()
    var state: GameState = GameState.PLAYER_TURN
        private set
    var result: GameResult? = null
        private set

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
        playerHand.addCard(deck.draw())
        dealerHand.addCard(deck.draw())
        playerHand.addCard(deck.draw())
        dealerHand.addCard(deck.draw())

        // Check for player blackjack
        if (playerHand.isBlackjack()) {
            playDealerTurn()
        }
    }

    fun hit(): Boolean {
        if (state != GameState.PLAYER_TURN) return false

        playerHand.addCard(deck.draw())

        if (playerHand.isBust()) {
            state = GameState.FINISHED
            result = GameResult.PLAYER_BUST
            return true
        }

        return true
    }

    fun stand(): Boolean {
        if (state != GameState.PLAYER_TURN) return false

        playDealerTurn()
        return true
    }

    private fun playDealerTurn() {
        state = GameState.DEALER_TURN

        // Dealer draws until 17 or higher
        while (dealerHand.getValue() < 17) {
            dealerHand.addCard(deck.draw())
        }

        state = GameState.FINISHED
        determineWinner()
    }

    private fun determineWinner() {
        val playerValue = playerHand.getValue()
        val dealerValue = dealerHand.getValue()

        result = when {
            playerHand.isBlackjack() && dealerHand.isBlackjack() -> GameResult.PUSH
            playerHand.isBlackjack() -> GameResult.PLAYER_BLACKJACK
            dealerHand.isBlackjack() -> GameResult.DEALER_WIN
            playerHand.isBust() -> GameResult.PLAYER_BUST
            dealerHand.isBust() -> GameResult.DEALER_BUST
            playerValue > dealerValue -> GameResult.PLAYER_WIN
            dealerValue > playerValue -> GameResult.DEALER_WIN
            else -> GameResult.PUSH
        }
    }

    fun isFinished(): Boolean = state == GameState.FINISHED

    fun isPlayerTurn(): Boolean = state == GameState.PLAYER_TURN
}
