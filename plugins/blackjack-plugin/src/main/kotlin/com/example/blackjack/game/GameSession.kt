package com.example.blackjack.game

import java.util.UUID

/** The current state of a Blackjack game. */
enum class GameState {
    /** Waiting for player to decide on insurance bet. */
    WAITING_FOR_INSURANCE,
    PLAYER_TURN,
    DEALER_TURN,
    FINISHED
}

/** Possible outcomes of a Blackjack hand. */
enum class GameResult {
    PLAYER_WIN,
    DEALER_WIN,
    /** A tie (push). */
    PUSH,
    PLAYER_BLACKJACK,
    PLAYER_BUST,
    DEALER_BUST,
    SURRENDERED
}

/** Result for a single hand including payout multiplier. */
data class HandResult(
    val hand: Hand,
    val result: GameResult,
    /** Payout multiplier (e.g., 1.0 win, 1.5 blackjack, -0.5 surrender, -1.0 loss). */
    val payout: Double
)

/**
 * Represents an active Blackjack game session for a player.
 *
 * Supports multiple hands (via splitting), double down, surrender, and insurance.
 *
 * @property playerId The unique ID of the player.
 * @property config The game configuration.
 */
class GameSession(
    val playerId: UUID,
    private val config: GameConfig = GameConfig()
) {
    val deck = Deck(config.numberOfDecks, config.reshuffleThreshold)

    /** All player hands (multiple when split). */
    val playerHands: MutableList<Hand> = mutableListOf()

    /** Index of the hand currently being played. */
    var currentHandIndex: Int = 0
        private set

    val dealerHand = Hand()

    var state: GameState = GameState.PLAYER_TURN
        private set

    /** Whether insurance was offered this round. */
    var insuranceOffered: Boolean = false
        private set

    /** Whether the player took insurance. */
    var insuranceTaken: Boolean = false
        private set

    /** Whether the dealer has blackjack (revealed after insurance decision). */
    var dealerHasBlackjack: Boolean = false
        private set

    /** Results for each hand (populated when game ends). */
    val handResults: MutableList<HandResult> = mutableListOf()

    /** The current player hand being played. */
    val playerHand: Hand
        get() = playerHands.getOrElse(currentHandIndex) { playerHands.first() }

    /** Returns `true` if the game has finished. */
    val isFinished: Boolean get() = state == GameState.FINISHED

    /** Returns `true` if it's currently the player's turn. */
    val isPlayerTurn: Boolean get() = state == GameState.PLAYER_TURN

    /** Returns `true` if waiting for insurance decision. */
    val isWaitingForInsurance: Boolean get() = state == GameState.WAITING_FOR_INSURANCE

    /** The primary game result (first hand). */
    val result: GameResult?
        get() = handResults.firstOrNull()?.result

    init {
        startNewGame()
    }

    private fun startNewGame() {
        if (deck.needsReshuffle()) {
            deck.reset()
        }

        playerHands.clear()
        playerHands.add(Hand())
        currentHandIndex = 0
        dealerHand.clear()
        state = GameState.PLAYER_TURN
        handResults.clear()
        insuranceOffered = false
        insuranceTaken = false
        dealerHasBlackjack = false

        // Deal initial cards: player, dealer, player, dealer
        playerHand += deck.draw()
        dealerHand += deck.draw()
        playerHand += deck.draw()
        dealerHand += deck.draw()

        // Check if insurance should be offered (dealer shows Ace)
        val dealerUpCard = dealerHand.cards.getOrNull(1)
        if (config.allowInsurance && dealerUpCard?.rank == Rank.ACE) {
            insuranceOffered = true
            state = GameState.WAITING_FOR_INSURANCE
            return
        }

        checkDealerBlackjackAndProceed()
    }

    private fun checkDealerBlackjackAndProceed() {
        val dealerUpCard = dealerHand.cards.getOrNull(1)

        if (config.dealerPeeks && dealerUpCard != null) {
            val shouldPeek = dealerUpCard.rank == Rank.ACE || dealerUpCard.value == 10
            if (shouldPeek && dealerHand.isBlackjack) {
                dealerHasBlackjack = true
                state = GameState.FINISHED
                determineAllResults()
                return
            }
        }

        if (playerHand.isBlackjack) {
            playDealerTurn()
        }
    }

    // === Insurance Actions ===

    /**
     * Player takes insurance bet.
     * @return `true` if action was valid.
     */
    fun takeInsurance(): Boolean {
        if (state != GameState.WAITING_FOR_INSURANCE) return false
        insuranceTaken = true
        proceedAfterInsuranceDecision()
        return true
    }

    /**
     * Player declines insurance bet.
     * @return `true` if action was valid.
     */
    fun declineInsurance(): Boolean {
        if (state != GameState.WAITING_FOR_INSURANCE) return false
        insuranceTaken = false
        proceedAfterInsuranceDecision()
        return true
    }

    private fun proceedAfterInsuranceDecision() {
        if (dealerHand.isBlackjack) {
            dealerHasBlackjack = true
            state = GameState.FINISHED
            determineAllResults()
            return
        }

        state = GameState.PLAYER_TURN
        if (playerHand.isBlackjack) {
            playDealerTurn()
        }
    }

    // === Player Actions ===

    /**
     * Player takes a hit (draws another card).
     * @return `true` if the action was valid.
     */
    fun hit(): Boolean {
        if (!isPlayerTurn) return false
        if (playerHand.isSplitAces && !config.allowHitSplitAces && playerHand.size >= 2) {
            return false
        }

        playerHand += deck.draw()

        if (playerHand.isBust) {
            advanceToNextHandOrDealer()
            return true
        }

        if (config.fiveCardCharlie && playerHand.size >= config.charlieCardCount && !playerHand.isBust) {
            advanceToNextHandOrDealer()
            return true
        }

        return true
    }

    /**
     * Player stands (ends their turn on current hand).
     * @return `true` if the action was valid.
     */
    fun stand(): Boolean {
        if (!isPlayerTurn) return false
        advanceToNextHandOrDealer()
        return true
    }

    /**
     * Player doubles down (doubles bet, receives exactly one card).
     * @return `true` if the action was valid.
     */
    fun doubleDown(): Boolean {
        if (!isPlayerTurn) return false
        if (!config.allowDoubleDown) return false
        if (!playerHand.canDoubleDown(config.doubleDownOn, config.allowDoubleAfterSplit)) return false

        playerHand.markDoubledDown()
        playerHand += deck.draw()
        advanceToNextHandOrDealer()
        return true
    }

    /**
     * Player splits their pair into two hands.
     * @return `true` if the action was valid.
     */
    fun split(): Boolean {
        if (!isPlayerTurn) return false
        if (!config.allowSplit) return false
        if (!playerHand.isPair) return false
        if (playerHands.size >= config.maxSplitHands) return false
        if (playerHand.isSplitAces && !config.allowResplitAces) return false

        val isAces = playerHand.cards[0].rank == Rank.ACE
        val secondCard = playerHand.removeLastCard() ?: return false

        // Create new hand with the second card
        val newHand = Hand(isFromSplit = true, isSplitAces = isAces)
        newHand += secondCard
        newHand += deck.draw()

        // Recreate current hand as split hand and deal new card
        val firstCard = playerHand.cards.first()
        playerHands[currentHandIndex] = Hand(isFromSplit = true, isSplitAces = isAces)
        playerHands[currentHandIndex] += firstCard
        playerHands[currentHandIndex] += deck.draw()

        // Insert new hand after current
        playerHands.add(currentHandIndex + 1, newHand)

        // Auto-stand on split aces if hitting not allowed
        if (isAces && !config.allowHitSplitAces) {
            advanceToNextHandOrDealer()
        }

        return true
    }

    /**
     * Player surrenders (forfeits half their bet).
     * @return `true` if the action was valid.
     */
    fun surrender(): Boolean {
        if (!isPlayerTurn) return false
        if (!config.allowSurrender) return false
        if (config.surrenderType == SurrenderType.NONE) return false
        if (playerHand.size != 2) return false
        if (playerHand.isFromSplit) return false

        playerHand.markSurrendered()
        state = GameState.FINISHED
        determineAllResults()
        return true
    }

    // === Game Flow ===

    private fun advanceToNextHandOrDealer() {
        if (currentHandIndex < playerHands.size - 1) {
            currentHandIndex++
            if (playerHand.isSplitAces && !config.allowHitSplitAces && playerHand.size >= 2) {
                advanceToNextHandOrDealer()
            }
            return
        }
        playDealerTurn()
    }

    private fun playDealerTurn() {
        state = GameState.DEALER_TURN

        val allBustedOrSurrendered = playerHands.all { it.isBust || it.hasSurrendered }
        if (allBustedOrSurrendered) {
            state = GameState.FINISHED
            determineAllResults()
            return
        }

        while (shouldDealerHit()) {
            dealerHand += deck.draw()
        }

        state = GameState.FINISHED
        determineAllResults()
    }

    private fun shouldDealerHit(): Boolean {
        val value = dealerHand.value
        if (value >= 18) return false
        if (value <= 16) return true

        // Soft 17 rule
        return if (config.dealerStandsOnSoft17) {
            false
        } else {
            dealerHand.isSoft
        }
    }

    private fun determineAllResults() {
        handResults.clear()
        for (hand in playerHands) {
            val result = determineHandResult(hand)
            val payout = calculatePayout(hand, result)
            handResults.add(HandResult(hand, result, payout))
        }
    }

    private fun determineHandResult(hand: Hand): GameResult {
        if (hand.hasSurrendered) return GameResult.SURRENDERED

        if (config.fiveCardCharlie && hand.size >= config.charlieCardCount && !hand.isBust) {
            return GameResult.PLAYER_WIN
        }

        return when {
            hand.isBlackjack && dealerHand.isBlackjack -> GameResult.PUSH
            hand.isBlackjack -> GameResult.PLAYER_BLACKJACK
            dealerHand.isBlackjack -> GameResult.DEALER_WIN
            hand.isBust -> GameResult.PLAYER_BUST
            dealerHand.isBust -> GameResult.DEALER_BUST
            hand.value > dealerHand.value -> GameResult.PLAYER_WIN
            dealerHand.value > hand.value -> GameResult.DEALER_WIN
            else -> GameResult.PUSH
        }
    }

    private fun calculatePayout(hand: Hand, result: GameResult): Double {
        val multiplier = if (hand.hasDoubledDown) 2.0 else 1.0

        return when (result) {
            GameResult.PLAYER_BLACKJACK -> config.blackjackPayout * multiplier
            GameResult.PLAYER_WIN, GameResult.DEALER_BUST -> 1.0 * multiplier
            GameResult.PUSH -> 0.0
            GameResult.SURRENDERED -> -0.5
            GameResult.PLAYER_BUST, GameResult.DEALER_WIN -> -1.0 * multiplier
        }
    }

    // === Query Methods ===

    /** Returns `true` if player can hit on current hand. */
    fun canHit(): Boolean {
        if (!isPlayerTurn) return false
        if (playerHand.isSplitAces && !config.allowHitSplitAces && playerHand.size >= 2) return false
        return true
    }

    /** Returns `true` if player can double down on current hand. */
    fun canDoubleDown(): Boolean {
        if (!isPlayerTurn) return false
        if (!config.allowDoubleDown) return false
        return playerHand.canDoubleDown(config.doubleDownOn, config.allowDoubleAfterSplit)
    }

    /** Returns `true` if player can split current hand. */
    fun canSplit(): Boolean {
        if (!isPlayerTurn) return false
        if (!config.allowSplit) return false
        if (!playerHand.isPair) return false
        if (playerHands.size >= config.maxSplitHands) return false
        if (playerHand.isSplitAces && !config.allowResplitAces) return false
        return true
    }

    /** Returns `true` if player can surrender current hand. */
    fun canSurrender(): Boolean {
        if (!isPlayerTurn) return false
        if (!config.allowSurrender) return false
        if (config.surrenderType == SurrenderType.NONE) return false
        if (playerHand.size != 2) return false
        if (playerHand.isFromSplit) return false
        return true
    }

    /** Total number of player hands (1 if no split). */
    fun getHandCount(): Int = playerHands.size

    /** Current hand number (1-based). */
    fun getCurrentHandNumber(): Int = currentHandIndex + 1

    /** Insurance payout multiplier if applicable. */
    fun getInsurancePayout(): Double {
        return when {
            insuranceTaken && dealerHasBlackjack -> config.insurancePayout
            insuranceTaken -> -0.5
            else -> 0.0
        }
    }

}
