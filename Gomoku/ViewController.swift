import UIKit

class ViewController: UIViewController {

    // --- Outlets ---
    @IBOutlet weak var statusLabel: UILabel!
    @IBOutlet weak var boardView: UIView!
    @IBOutlet weak var resetButton: UIButton!

    // --- Game Constants ---
    let boardSize = 15
    var cellSize: CGFloat = 0
    var boardPadding: CGFloat = 10

    // --- Game State ---
    enum Player { case black, white }
    enum CellState { case empty, black, white }
    var currentPlayer: Player = .black
    var board: [[CellState]] = []
    var gameOver = false
    var pieceViews: [[UIView?]] = []
    
    // --- Adaptive Setup UI Properties ---
    private var setupPortraitConstraints: [NSLayoutConstraint] = []
    private var setupLandscapeConstraints: [NSLayoutConstraint] = []
    private var currentSetupConstraints: [NSLayoutConstraint] = [] // Track active set

    // --- AI Control ---
    enum AIDifficulty { case easy, medium, hard } // Keep 'hard' enum value
    let aiPlayer: Player = .white
    private var selectedDifficulty: AIDifficulty = .easy
    var isAiTurn: Bool { currentGameMode == .humanVsAI && currentPlayer == aiPlayer }

    // --- Layer References ---
    var backgroundGradientLayer: CAGradientLayer?
    var woodBackgroundLayers: [CALayer] = []
    private var lastDrawnBoardBounds: CGRect = .zero
    private var winningLineLayer: CAShapeLayer? // For win line

    // --- Game Setup State ---
    enum GameState { case setup, playing }
    enum GameMode { case humanVsHuman, humanVsAI }
    private var currentGameState: GameState = .setup
    private var currentGameMode: GameMode = .humanVsHuman

    // --- Setup UI Elements ---
    private let gameTitleLabel = UILabel()
    private let setupTitleLabel = UILabel()
    private let startEasyAIButton = UIButton(type: .system)
    private let startMediumAIButton = UIButton(type: .system)
    private let startHardAIButton = UIButton(type: .system) // ADD HARD AI BUTTON BACK
    private let startHvsHButton = UIButton(type: .system)
    private var setupUIElements: [UIView] = []

    // --- Main Menu Button ---
    private let mainMenuButton = UIButton(type: .system)
    
    // --- Visual Polish Properties ---
    private var lastMovePosition: Position? = nil
    private var lastMoveIndicatorLayer: CALayer?
    private var turnIndicatorBorderLayer: CALayer?
    private var shakeAnimation: CABasicAnimation? // To create shake only once
    private var turnIndicatorView: UIView?

    // --- Game Over Overlay UI Elements ---
    private let gameOverOverlayView = UIVisualEffectView()
    private let gameOverStatusLabel = UILabel()
    private let playAgainButton = UIButton(type: .system)
    private let overlayMainMenuButton = UIButton(type: .system)
    private var gameOverUIElements: [UIView] = []

    // --- Constraint Activation Flag ---
    private var constraintsActivated = false

    // --- Lifecycle Methods ---
    override func viewDidLoad() {
        super.viewDidLoad()
        print("viewDidLoad starting...")
        setupMainBackground()
        styleStatusLabel()
        boardView.backgroundColor = .clear
        styleResetButton()
        createMainMenuButton()
        createSetupUI() // Will now include Hard AI button
        createNewGameOverUI()
        setupTurnIndicatorView()
        setupTurnIndicatorBorder()
        setupNewGameVariablesOnly()
        showSetupUI()
        print("viewDidLoad completed.")
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        if !constraintsActivated {
            print("viewWillLayoutSubviews: Setting up ALL constraints for the first time.")
            setupConstraints() // Game Elements
            setupSetupUIConstraints() // Setup UI (Creates Sets) -> Needs update for Hard button
            setupMainMenuButtonConstraints() // Menu Button
            setupGameOverUIConstraints() // Game Over Overlay
            constraintsActivated = true
        }
         // Apply correct adaptive constraints for setup UI based on current size
         applyAdaptiveSetupConstraints()
    }
    
    // Called once from viewDidLoad after constraints are set
    func setupTurnIndicatorBorder() {
        guard turnIndicatorBorderLayer == nil else { return } // Create only once

        let borderLayer = CALayer()
        borderLayer.borderWidth = 3.0 // Thickness of indicator
        borderLayer.cornerRadius = 10 + 4 // Match board corner radius + padding (assuming board corner radius is 10)
        borderLayer.masksToBounds = true // Needed if using background color instead of border
        borderLayer.borderColor = UIColor.clear.cgColor // Start clear
        // Position needs to be updated in viewDidLayoutSubviews
        boardView.layer.addSublayer(borderLayer) // Add as sublayer of boardView
        self.turnIndicatorBorderLayer = borderLayer
        print("Turn indicator border layer created.")
    }

    // --- Function to Update Turn Indicator Appearance ---
    func updateTurnIndicator() {
        guard let borderLayer = turnIndicatorBorderLayer else { return }

        let targetColor: UIColor
        if gameOver {
            targetColor = .clear // Hide border when game is over
        } else {
            targetColor = (currentPlayer == .black) ? .black : .white
        }

        // Animate border color change
        let colorAnimation = CABasicAnimation(keyPath: "borderColor")
        // Ensure we animate from the current presentation layer's color if mid-animation
        colorAnimation.fromValue = borderLayer.presentation()?.borderColor ?? borderLayer.borderColor
        colorAnimation.toValue = targetColor.withAlphaComponent(0.6).cgColor // Semi-transparent
        colorAnimation.duration = 0.3
        colorAnimation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

        // Update the model layer immediately
        borderLayer.borderColor = targetColor.withAlphaComponent(0.6).cgColor
        // Add the animation
        borderLayer.add(colorAnimation, forKey: "borderColorChange")

        // Don't print here, too verbose
        // print("Updated turn indicator color for \(currentPlayer)")
    }


    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Limit frequency of prints
        // print("viewDidLayoutSubviews triggered. State: \(currentGameState)")
        self.backgroundGradientLayer?.frame = self.view.bounds

        // Debug Title Frame
        // if currentGameState == .setup {
        //     print("Setup State - Game Title Label - Frame: \(gameTitleLabel.frame), IsHidden: \(gameTitleLabel.isHidden)")
        // }

        guard currentGameState == .playing else {
            // print("viewDidLayoutSubviews: Not in playing state, skipping board draw.")
            return
        }
        
        // Update turn indicator frame to match boardView bounds + padding
        if let borderLayer = turnIndicatorBorderLayer {
             let boardCornerRadius = boardView.layer.cornerRadius // Get current radius
             borderLayer.frame = boardView.bounds.insetBy(dx: -4, dy: -4) // Slightly outside board bounds
             borderLayer.cornerRadius = boardCornerRadius + 4 // Keep it relative
        }


        let currentBoardBounds = boardView.bounds
        // print("viewDidLayoutSubviews - BoardView Bounds: \(currentBoardBounds)")
        guard currentBoardBounds.width > 0, currentBoardBounds.height > 0 else {
            // print("viewDidLayoutSubviews: boardView bounds zero or invalid, skipping draw.")
            if lastDrawnBoardBounds != .zero { lastDrawnBoardBounds = .zero }
            return
        }

        let potentialCellSize = calculateCellSize()
        // print("viewDidLayoutSubviews - Potential Cell Size: \(potentialCellSize)")
        guard potentialCellSize > 0 else {
            // print("viewDidLayoutSubviews: Potential cell size calculation invalid, skipping draw.")
            if lastDrawnBoardBounds != .zero { lastDrawnBoardBounds = .zero }
            return
        }

        if currentBoardBounds != lastDrawnBoardBounds || self.cellSize == 0 {
            print("--> Board bounds changed or initial draw needed. Performing visual update.")
            self.cellSize = potentialCellSize
            // Ensure boardView has corner radius BEFORE drawing wood background
            boardView.layer.cornerRadius = 10 // Set corner radius here if not set elsewhere
            boardView.layer.masksToBounds = true // Important for sublayers respecting corners
            drawProceduralWoodBackground() // Draw background first
            drawBoard()                // Draw grid lines over background
            redrawPieces()             // Draw pieces on top
            lastDrawnBoardBounds = currentBoardBounds
            print("viewDidLayoutSubviews: Visual update complete with cellSize: \(self.cellSize)")

             // Redraw winning line if game ended before layout change
             if gameOver, let lastWinPos = self.lastWinningPositions {
                  drawWinningLine(positions: lastWinPos)
             }
             // Redraw last move indicator if active
             if let lastPos = self.lastMovePosition, !gameOver {
                 // Remove old one visually before redrawing
                 lastMoveIndicatorLayer?.removeFromSuperlayer()
                 lastMoveIndicatorLayer = nil
                 showLastMoveIndicator(at: lastPos) // Recreate with new cell size
             }

        } else {
             // print("viewDidLayoutSubviews: Board bounds haven't changed, no redraw needed.")
        }
        
        // Ensure initial turn indicator update
        if currentGameState == .playing && !gameOver && turnIndicatorBorderLayer?.borderColor == UIColor.clear.cgColor {
             updateTurnIndicator()
        }
    }
    
    // --- Stored property for winning positions to redraw on layout change ---
    private var lastWinningPositions: [Position]? = nil


    // --- Constraint Setup (Game elements) ---
    func setupConstraints() {
        guard let statusLabel = statusLabel, let boardView = boardView, let resetButton = resetButton else { print("Error: Outlets not connected for game elements!"); return }
        guard !self.view.constraints.contains(where: { $0.firstItem === boardView || $0.secondItem === boardView }) else { return }

        print("Setting up game element constraints..."); statusLabel.translatesAutoresizingMaskIntoConstraints = false; boardView.translatesAutoresizingMaskIntoConstraints = false; resetButton.translatesAutoresizingMaskIntoConstraints = false
        let safeArea = view.safeAreaLayoutGuide
        let centerXConstraint = boardView.centerXAnchor.constraint(equalTo: safeArea.centerXAnchor); let centerYConstraint = boardView.centerYAnchor.constraint(equalTo: safeArea.centerYAnchor)
        let aspectRatioConstraint = boardView.heightAnchor.constraint(equalTo: boardView.widthAnchor, multiplier: 1.0); aspectRatioConstraint.priority = .required; let leadingConstraint = boardView.leadingAnchor.constraint(greaterThanOrEqualTo: safeArea.leadingAnchor, constant: 20)
        let trailingConstraint = boardView.trailingAnchor.constraint(lessThanOrEqualTo: safeArea.trailingAnchor, constant: -20); let topConstraint = boardView.topAnchor.constraint(greaterThanOrEqualTo: safeArea.topAnchor, constant: 80)
        let bottomConstraint = boardView.bottomAnchor.constraint(lessThanOrEqualTo: safeArea.bottomAnchor, constant: -80); let widthConstraint = boardView.widthAnchor.constraint(equalTo: safeArea.widthAnchor, constant: -40); widthConstraint.priority = .defaultHigh
        let heightConstraint = boardView.heightAnchor.constraint(equalTo: safeArea.heightAnchor, constant: -160); heightConstraint.priority = .defaultHigh
        NSLayoutConstraint.activate([centerXConstraint, centerYConstraint, aspectRatioConstraint, leadingConstraint, trailingConstraint, topConstraint, bottomConstraint, widthConstraint, heightConstraint])
        NSLayoutConstraint.activate([statusLabel.topAnchor.constraint(equalTo: safeArea.topAnchor, constant: 20), statusLabel.leadingAnchor.constraint(greaterThanOrEqualTo: safeArea.leadingAnchor, constant: 20), statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: safeArea.trailingAnchor, constant: -20), statusLabel.centerXAnchor.constraint(equalTo: safeArea.centerXAnchor)])
        NSLayoutConstraint.activate([resetButton.bottomAnchor.constraint(equalTo: safeArea.bottomAnchor, constant: -30), resetButton.centerXAnchor.constraint(equalTo: safeArea.centerXAnchor), resetButton.leadingAnchor.constraint(greaterThanOrEqualTo: safeArea.leadingAnchor, constant: 30), resetButton.trailingAnchor.constraint(lessThanOrEqualTo: safeArea.trailingAnchor, constant: -30)])
        print("Game element constraints activated.")
    }

    // --- Setup UI Creation & Management (WITH HARD BUTTON) ---
    func createSetupUI() {
        print("Creating Setup UI")
        gameTitleLabel.translatesAutoresizingMaskIntoConstraints = false; gameTitleLabel.text = "Gomoku"; gameTitleLabel.font = UIFont.systemFont(ofSize: 48, weight: .bold); gameTitleLabel.textColor = UIColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1.0); gameTitleLabel.textAlignment = .center; gameTitleLabel.layer.shadowColor = UIColor.black.cgColor; gameTitleLabel.layer.shadowOffset = CGSize(width: 0, height: 2); gameTitleLabel.layer.shadowRadius = 4.0; gameTitleLabel.layer.shadowOpacity = 0.2; gameTitleLabel.layer.masksToBounds = false; view.addSubview(gameTitleLabel)
        setupTitleLabel.translatesAutoresizingMaskIntoConstraints = false; setupTitleLabel.text = "Choose Game Mode"; setupTitleLabel.font = UIFont.systemFont(ofSize: 26, weight: .bold); setupTitleLabel.textColor = UIColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1.0); setupTitleLabel.textAlignment = .center; view.addSubview(setupTitleLabel)

        // Buttons (Including Hard)
        startEasyAIButton.translatesAutoresizingMaskIntoConstraints = false; configureSetupButton(startEasyAIButton, color: UIColor(red: 0.8, green: 0.95, blue: 0.85, alpha: 1.0)); startEasyAIButton.setTitle("vs AI (Easy)", for: .normal); startEasyAIButton.addTarget(self, action: #selector(didTapStartEasyAI), for: .touchUpInside); view.addSubview(startEasyAIButton)
        startMediumAIButton.translatesAutoresizingMaskIntoConstraints = false; configureSetupButton(startMediumAIButton, color: UIColor(red: 0.95, green: 0.9, blue: 0.75, alpha: 1.0)); startMediumAIButton.setTitle("vs AI (Medium)", for: .normal); startMediumAIButton.addTarget(self, action: #selector(didTapStartMediumAI), for: .touchUpInside); view.addSubview(startMediumAIButton)
        startHardAIButton.translatesAutoresizingMaskIntoConstraints = false; configureSetupButton(startHardAIButton, color: UIColor(red: 0.95, green: 0.75, blue: 0.75, alpha: 1.0)); startHardAIButton.setTitle("vs AI (Hard)", for: .normal); startHardAIButton.addTarget(self, action: #selector(didTapStartHardAI), for: .touchUpInside); view.addSubview(startHardAIButton) // Add Hard button
        startHvsHButton.translatesAutoresizingMaskIntoConstraints = false; configureSetupButton(startHvsHButton, color: UIColor(red: 0.85, green: 0.85, blue: 0.95, alpha: 1.0)); startHvsHButton.setTitle("Human vs Human", for: .normal); startHvsHButton.addTarget(self, action: #selector(didTapStartHvsH), for: .touchUpInside); view.addSubview(startHvsHButton)

        // Update stored elements array (now 6 elements)
        setupUIElements = [gameTitleLabel, setupTitleLabel, startEasyAIButton, startMediumAIButton, startHardAIButton, startHvsHButton]
    }

    // Helper to configure common button styles
    func configureSetupButton(_ button: UIButton, color: UIColor) {
        // ... (button styling remains the same) ...
        button.titleLabel?.font = UIFont.systemFont(ofSize: 18, weight: .semibold);
        button.backgroundColor = color;
        button.setTitleColor(.darkText, for: .normal);
        button.layer.cornerRadius = 14
        if #available(iOS 15.0, *) {
            var config = UIButton.Configuration.filled()
            config.baseBackgroundColor = color; config.baseForegroundColor = .darkText
            config.contentInsets = NSDirectionalEdgeInsets(top: 15, leading: 30, bottom: 15, trailing: 30) // Adjusted padding slightly
            config.cornerStyle = .large
            config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
                  var outgoing = incoming
                  outgoing.font = UIFont.systemFont(ofSize: 22, weight: .bold) // Slightly smaller font?
                  return outgoing
              }
            button.configuration = config
        } else {
            button.contentEdgeInsets = UIEdgeInsets(top: 15, left: 30, bottom: 15, right: 30) // Adjusted padding slightly
        }
        button.layer.shadowColor = UIColor.black.cgColor
         button.layer.shadowOffset = CGSize(width: 0, height: 1)
         button.layer.shadowRadius = 3
         button.layer.shadowOpacity = 0.15
         button.layer.masksToBounds = false
    }

    // --- UPDATE Setup UI Constraints (to include Hard Button) ---
     func setupSetupUIConstraints() {
         print("Setting up Setup UI constraints (V4 - With Hard Button)")
         setupPortraitConstraints.removeAll(); setupLandscapeConstraints.removeAll()
         guard setupUIElements.count == 6 else { print("Error: Setup UI elements count mismatch (\(setupUIElements.count)). Expected 6."); return }

         let safeArea = view.safeAreaLayoutGuide
         let verticalSpacingMultiplier: CGFloat = 0.04 // Tighter spacing
         let buttonHeightMultiplier: CGFloat = 0.09
         let buttonWidthMultiplier: CGFloat = 0.65

         // --- Portrait ---
         setupPortraitConstraints = [
             gameTitleLabel.topAnchor.constraint(equalTo: safeArea.topAnchor, constant: view.bounds.height * 0.12), // Slightly higher
             gameTitleLabel.centerXAnchor.constraint(equalTo: safeArea.centerXAnchor),
             gameTitleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: safeArea.leadingAnchor, constant: 20),
             gameTitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: safeArea.trailingAnchor, constant: -20),

             setupTitleLabel.topAnchor.constraint(equalTo: gameTitleLabel.bottomAnchor, constant: view.bounds.height * 0.02),
             setupTitleLabel.centerXAnchor.constraint(equalTo: safeArea.centerXAnchor),
             setupTitleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: safeArea.leadingAnchor, constant: 20),
             setupTitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: safeArea.trailingAnchor, constant: -20),

             // Buttons Stacked Vertically
             startEasyAIButton.topAnchor.constraint(equalTo: setupTitleLabel.bottomAnchor, constant: view.bounds.height * 0.05),
             startEasyAIButton.centerXAnchor.constraint(equalTo: safeArea.centerXAnchor),
             startEasyAIButton.widthAnchor.constraint(equalTo: safeArea.widthAnchor, multiplier: buttonWidthMultiplier),
             startEasyAIButton.heightAnchor.constraint(equalTo: safeArea.heightAnchor, multiplier: buttonHeightMultiplier),

             startMediumAIButton.topAnchor.constraint(equalTo: startEasyAIButton.bottomAnchor, constant: view.bounds.height * verticalSpacingMultiplier),
             startMediumAIButton.centerXAnchor.constraint(equalTo: safeArea.centerXAnchor),
             startMediumAIButton.widthAnchor.constraint(equalTo: startEasyAIButton.widthAnchor),
             startMediumAIButton.heightAnchor.constraint(equalTo: startEasyAIButton.heightAnchor),

             startHardAIButton.topAnchor.constraint(equalTo: startMediumAIButton.bottomAnchor, constant: view.bounds.height * verticalSpacingMultiplier), // Add Hard Button
             startHardAIButton.centerXAnchor.constraint(equalTo: safeArea.centerXAnchor),
             startHardAIButton.widthAnchor.constraint(equalTo: startEasyAIButton.widthAnchor),
             startHardAIButton.heightAnchor.constraint(equalTo: startEasyAIButton.heightAnchor),

             startHvsHButton.topAnchor.constraint(equalTo: startHardAIButton.bottomAnchor, constant: view.bounds.height * verticalSpacingMultiplier), // Below Hard Button
             startHvsHButton.centerXAnchor.constraint(equalTo: safeArea.centerXAnchor),
             startHvsHButton.widthAnchor.constraint(equalTo: startEasyAIButton.widthAnchor),
             startHvsHButton.heightAnchor.constraint(equalTo: startEasyAIButton.heightAnchor),
         ]

         // --- Landscape ---
         // Keep landscape similar, just add the hard button in the stack
         let landscapeButtonWidthMultiplier: CGFloat = 0.35
         let landscapeVerticalSpacing: CGFloat = view.bounds.height * 0.03 // Tighter vertical space

         setupLandscapeConstraints = [
             gameTitleLabel.topAnchor.constraint(equalTo: safeArea.topAnchor, constant: view.bounds.height * 0.05),
             gameTitleLabel.centerXAnchor.constraint(equalTo: safeArea.centerXAnchor), // Centered Title
             // gameTitleLabel.leadingAnchor.constraint(equalTo: safeArea.leadingAnchor, constant: 40), // Keep centered

             setupTitleLabel.topAnchor.constraint(equalTo: gameTitleLabel.bottomAnchor, constant: view.bounds.height * 0.02),
             setupTitleLabel.centerXAnchor.constraint(equalTo: safeArea.centerXAnchor),
             // setupTitleLabel.leadingAnchor.constraint(equalTo: gameTitleLabel.leadingAnchor),

             // Stack buttons centrally
             startEasyAIButton.topAnchor.constraint(equalTo: setupTitleLabel.bottomAnchor, constant: view.bounds.height * 0.05),
             startEasyAIButton.centerXAnchor.constraint(equalTo: safeArea.centerXAnchor),
             startEasyAIButton.widthAnchor.constraint(equalTo: safeArea.widthAnchor, multiplier: landscapeButtonWidthMultiplier),
             startEasyAIButton.heightAnchor.constraint(equalTo: safeArea.heightAnchor, multiplier: buttonHeightMultiplier * 1.2), // Slightly taller buttons in landscape

             startMediumAIButton.topAnchor.constraint(equalTo: startEasyAIButton.bottomAnchor, constant: landscapeVerticalSpacing),
             startMediumAIButton.centerXAnchor.constraint(equalTo: safeArea.centerXAnchor),
             startMediumAIButton.widthAnchor.constraint(equalTo: startEasyAIButton.widthAnchor),
             startMediumAIButton.heightAnchor.constraint(equalTo: startEasyAIButton.heightAnchor),

             startHardAIButton.topAnchor.constraint(equalTo: startMediumAIButton.bottomAnchor, constant: landscapeVerticalSpacing),
             startHardAIButton.centerXAnchor.constraint(equalTo: safeArea.centerXAnchor),
             startHardAIButton.widthAnchor.constraint(equalTo: startEasyAIButton.widthAnchor),
             startHardAIButton.heightAnchor.constraint(equalTo: startEasyAIButton.heightAnchor),

             startHvsHButton.topAnchor.constraint(equalTo: startHardAIButton.bottomAnchor, constant: landscapeVerticalSpacing),
             startHvsHButton.centerXAnchor.constraint(equalTo: safeArea.centerXAnchor),
             startHvsHButton.widthAnchor.constraint(equalTo: startEasyAIButton.widthAnchor),
             startHvsHButton.heightAnchor.constraint(equalTo: startEasyAIButton.heightAnchor),
         ]
         print("Setup UI constraint sets V4 created.")
     }


    // Helper to Activate/Deactivate Adaptive Constraints
    func applyAdaptiveSetupConstraints() {
        guard constraintsActivated else { return }
        let isLandscape = view.bounds.width > view.bounds.height
        let targetConstraints = isLandscape ? setupLandscapeConstraints : setupPortraitConstraints
        if currentSetupConstraints == targetConstraints && !currentSetupConstraints.isEmpty { return }
        // print("Applying setup constraints for \(isLandscape ? "Landscape" : "Portrait").")
        if !currentSetupConstraints.isEmpty { /* print("Deactivating \(currentSetupConstraints.count) old setup constraints."); */ NSLayoutConstraint.deactivate(currentSetupConstraints) }
        if !targetConstraints.isEmpty { /* print("Activating \(targetConstraints.count) new setup constraints."); */ NSLayoutConstraint.activate(targetConstraints); currentSetupConstraints = targetConstraints }
        else { print("Warning: Target constraint set is empty for \(isLandscape ? "Landscape" : "Portrait")."); currentSetupConstraints = [] }
    }

    // --- Main Menu Button Creation/Constraints ---
    func createMainMenuButton() {
        print("Creating Main Menu Button"); mainMenuButton.translatesAutoresizingMaskIntoConstraints = false; if #available(iOS 15.0, *) { var config = UIButton.Configuration.plain(); config.title = "‹ Menu"; config.titleAlignment = .leading; config.baseForegroundColor = UIColor.systemBlue; config.contentInsets = NSDirectionalEdgeInsets(top: 5, leading: 0, bottom: 5, trailing: 10); mainMenuButton.configuration = config } else { mainMenuButton.setTitle("‹ Menu", for: .normal); mainMenuButton.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .medium); mainMenuButton.setTitleColor(UIColor.systemBlue, for: .normal); mainMenuButton.contentEdgeInsets = UIEdgeInsets(top: 5, left: 0, bottom: 5, right: 10) }; mainMenuButton.backgroundColor = .clear; mainMenuButton.addTarget(self, action: #selector(didTapMainMenu), for: .touchUpInside); mainMenuButton.isHidden = true; view.addSubview(mainMenuButton)
    }
    func setupMainMenuButtonConstraints() {
        print("Setting up Main Menu Button constraints"); let safeArea = view.safeAreaLayoutGuide; NSLayoutConstraint.activate([ mainMenuButton.topAnchor.constraint(equalTo: safeArea.topAnchor, constant: 15), mainMenuButton.leadingAnchor.constraint(equalTo: safeArea.leadingAnchor, constant: 20) ])
    }

    // --- Game Over UI Creation/Constraints ---
    func createNewGameOverUI() {
         print("Creating Game Over UI with Blur"); gameOverOverlayView.translatesAutoresizingMaskIntoConstraints = false; gameOverOverlayView.effect = UIBlurEffect(style: .systemMaterialDark); gameOverOverlayView.layer.cornerRadius = 15; gameOverOverlayView.layer.masksToBounds = true; gameOverOverlayView.isHidden = true
         gameOverOverlayView.contentView.addSubview(gameOverStatusLabel); gameOverOverlayView.contentView.addSubview(playAgainButton); gameOverOverlayView.contentView.addSubview(overlayMainMenuButton); view.addSubview(gameOverOverlayView)
         gameOverStatusLabel.translatesAutoresizingMaskIntoConstraints = false; gameOverStatusLabel.font = UIFont.systemFont(ofSize: 32, weight: .bold); gameOverStatusLabel.textColor = .white; gameOverStatusLabel.textAlignment = .center; gameOverStatusLabel.numberOfLines = 0
         playAgainButton.translatesAutoresizingMaskIntoConstraints = false; configureGameOverButton(playAgainButton, title: "Play Again", color: UIColor.systemGreen.withAlphaComponent(0.8)); playAgainButton.addTarget(self, action: #selector(didTapPlayAgain), for: .touchUpInside)
         overlayMainMenuButton.translatesAutoresizingMaskIntoConstraints = false; configureGameOverButton(overlayMainMenuButton, title: "Main Menu", color: UIColor.systemBlue.withAlphaComponent(0.8)); overlayMainMenuButton.addTarget(self, action: #selector(didTapMainMenu), for: .touchUpInside)
         gameOverUIElements = [gameOverOverlayView, gameOverStatusLabel, playAgainButton, overlayMainMenuButton]
    }
    func configureGameOverButton(_ button: UIButton, title: String, color: UIColor) {
        button.setTitle(title, for: .normal); if #available(iOS 15.0, *) { var config = UIButton.Configuration.filled(); config.baseBackgroundColor = color; config.baseForegroundColor = .white; config.cornerStyle = .medium; config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in var outgoing = incoming; outgoing.font = UIFont.systemFont(ofSize: 18, weight: .semibold); return outgoing }; config.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 20, bottom: 10, trailing: 20); button.configuration = config } else { button.backgroundColor = color; button.setTitleColor(.white, for: .normal); button.titleLabel?.font = UIFont.systemFont(ofSize: 18, weight: .semibold); button.layer.cornerRadius = 8; button.contentEdgeInsets = UIEdgeInsets(top: 10, left: 20, bottom: 10, right: 20) }; button.layer.shadowColor = UIColor.black.cgColor; button.layer.shadowOffset = CGSize(width: 0, height: 1); button.layer.shadowRadius = 3; button.layer.shadowOpacity = 0.3; button.layer.masksToBounds = false
    }
    func setupGameOverUIConstraints() {
         print("Setting up Game Over UI constraints"); let safeArea = view.safeAreaLayoutGuide; let buttonSpacing: CGFloat = 20; let overlayContentView = gameOverOverlayView.contentView
         NSLayoutConstraint.activate([ gameOverOverlayView.centerXAnchor.constraint(equalTo: safeArea.centerXAnchor), gameOverOverlayView.centerYAnchor.constraint(equalTo: safeArea.centerYAnchor), gameOverOverlayView.widthAnchor.constraint(equalTo: safeArea.widthAnchor, multiplier: 0.7), gameOverOverlayView.heightAnchor.constraint(lessThanOrEqualTo: safeArea.heightAnchor, multiplier: 0.5), gameOverStatusLabel.topAnchor.constraint(equalTo: overlayContentView.topAnchor, constant: 30), gameOverStatusLabel.leadingAnchor.constraint(equalTo: overlayContentView.leadingAnchor, constant: 20), gameOverStatusLabel.trailingAnchor.constraint(equalTo: overlayContentView.trailingAnchor, constant: -20), playAgainButton.topAnchor.constraint(equalTo: gameOverStatusLabel.bottomAnchor, constant: 30), playAgainButton.centerXAnchor.constraint(equalTo: overlayContentView.centerXAnchor), overlayMainMenuButton.topAnchor.constraint(equalTo: playAgainButton.bottomAnchor, constant: buttonSpacing), overlayMainMenuButton.centerXAnchor.constraint(equalTo: overlayContentView.centerXAnchor), overlayMainMenuButton.widthAnchor.constraint(equalTo: playAgainButton.widthAnchor), overlayMainMenuButton.bottomAnchor.constraint(lessThanOrEqualTo: overlayContentView.bottomAnchor, constant: -30) ])
    }
    
    // --- Turn Indicator (Underline) Setup/Update ---
    func setupTurnIndicatorView() {
        guard statusLabel != nil else { return } // Need status label to anchor to
        let indicator = UIView(); indicator.translatesAutoresizingMaskIntoConstraints = false; indicator.backgroundColor = .clear; indicator.layer.cornerRadius = 1.5; indicator.isHidden = true; view.addSubview(indicator); self.turnIndicatorView = indicator
        NSLayoutConstraint.activate([indicator.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 4), indicator.heightAnchor.constraint(equalToConstant: 3), indicator.centerXAnchor.constraint(equalTo: statusLabel.centerXAnchor)])
        print("Turn indicator view created.")
    }
    func updateTurnIndicatorLine() {
        guard let indicator = turnIndicatorView, let label = statusLabel else { return }
        let targetColor: UIColor; let targetWidth: CGFloat
        if gameOver || currentGameState != .playing { targetColor = .clear; targetWidth = 0 }
        else { targetColor = (currentPlayer == .black) ? .black : UIColor(white: 0.9, alpha: 0.9); targetWidth = label.intrinsicContentSize.width * 0.6 }
        UIView.animate(withDuration: 0.35, delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 0.5, options: .curveEaseOut, animations: {
            indicator.backgroundColor = targetColor
             if let widthConstraint = indicator.constraints.first(where: { $0.firstAttribute == .width }) { widthConstraint.constant = targetWidth }
             else { indicator.widthAnchor.constraint(equalToConstant: targetWidth).isActive = true }
             indicator.superview?.layoutIfNeeded()
        }, completion: nil)
        indicator.isHidden = (gameOver || currentGameState != .playing)
        // print("Updated turn indicator line for \(currentPlayer)") // Too verbose
    }

    // --- Visibility Functions ---
    func showSetupUI() {
        print("Showing Setup UI"); currentGameState = .setup; statusLabel.isHidden = true; boardView.isHidden = true; resetButton.isHidden = true; mainMenuButton.isHidden = true; gameOverOverlayView.isHidden = true; turnIndicatorView?.isHidden = true; turnIndicatorBorderLayer?.isHidden = true; setupUIElements.forEach { $0.isHidden = false }; gameTitleLabel.isHidden = false; print("showSetupUI - Game Title isHidden: \(gameTitleLabel.isHidden)"); boardView.gestureRecognizers?.forEach { boardView.removeGestureRecognizer($0) }
    }
    func showGameUI() {
        print("Showing Game UI"); currentGameState = .playing; statusLabel.isHidden = false; boardView.isHidden = false; resetButton.isHidden = false; mainMenuButton.isHidden = false; gameOverOverlayView.isHidden = true; turnIndicatorView?.isHidden = false; turnIndicatorBorderLayer?.isHidden = false; setupUIElements.forEach { $0.isHidden = true }; gameTitleLabel.isHidden = true; print("showGameUI - Game Title isHidden: \(gameTitleLabel.isHidden)"); if boardView.gestureRecognizers?.isEmpty ?? true { addTapGestureRecognizer() }; DispatchQueue.main.async { self.updateTurnIndicatorLine(); self.updateTurnIndicator() } // Update both indicators
    }
    func showGameOverOverlay(message: String) {
        print("Showing Game Over Overlay: \(message)"); gameOverStatusLabel.text = message; gameOverOverlayView.isHidden = false; gameOverOverlayView.alpha = 0; gameOverOverlayView.transform = CGAffineTransform(scaleX: 1.1, y: 1.1); view.bringSubviewToFront(gameOverOverlayView); resetButton.isHidden = true; mainMenuButton.isHidden = true; UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0.3, options: .curveEaseOut, animations: { self.gameOverOverlayView.alpha = 1.0; self.gameOverOverlayView.transform = .identity }, completion: nil); view.isUserInteractionEnabled = true
        turnIndicatorBorderLayer?.isHidden = true // Hide border on game over
        turnIndicatorView?.isHidden = true      // Hide underline on game over
    }
    func hideGameOverOverlay() {
         print("Hiding Game Over Overlay"); UIView.animate(withDuration: 0.2, animations: { self.gameOverOverlayView.alpha = 0.0; self.gameOverOverlayView.transform = CGAffineTransform(scaleX: 0.9, y: 0.9) }) { _ in self.gameOverOverlayView.isHidden = true; self.gameOverOverlayView.transform = .identity; if self.currentGameState == .playing { self.resetButton.isHidden = false; self.mainMenuButton.isHidden = false; self.turnIndicatorBorderLayer?.isHidden = self.gameOver; self.turnIndicatorView?.isHidden = self.gameOver } } // Show indicators again if game restarted
    }

    // --- Button Actions ---
    @objc func didTapPlayAgain() { print("Play Again tapped"); hideGameOverOverlay(); startGame(mode: currentGameMode, difficulty: selectedDifficulty) }
    @objc func didTapMainMenu() { print("Main Menu button tapped"); hideGameOverOverlay(); showSetupUI() }
    @objc func didTapStartEasyAI() { print("Start Easy AI tapped"); startGame(mode: .humanVsAI, difficulty: .easy) }
    @objc func didTapStartMediumAI() { print("Start Medium AI tapped"); startGame(mode: .humanVsAI, difficulty: .medium) }
    @objc func didTapStartHardAI() { print("Start Hard AI tapped"); startGame(mode: .humanVsAI, difficulty: .hard) } // ADD Hard AI action
    @objc func didTapStartHvsH() { print("Start Human vs Human tapped"); startGame(mode: .humanVsHuman, difficulty: .easy) } // HvsH defaults to easy difficulty internally, which is fine

    func startGame(mode: GameMode, difficulty: AIDifficulty) {
         print("Starting game mode: \(mode), Difficulty: \(difficulty)");
         self.currentGameMode = mode;
         // Store selected difficulty only if AI mode, default otherwise
         self.selectedDifficulty = (mode == .humanVsAI) ? difficulty : .easy
         showGameUI();
         setupNewGame();
         view.setNeedsLayout() // Crucial for layout changes before board drawing
         view.layoutIfNeeded() // Force layout pass NOW
         print("Game started.")
         // If AI is first player (e.g. AI is Black), trigger its turn
         if isAiTurn && !gameOver {
             view.isUserInteractionEnabled = false // Disable input immediately
             statusLabel.text = "Computer (\(selectedDifficulty)) Turn..."
             print("AI (\(selectedDifficulty)) starts first.")
             // Add a slight delay for user orientation
             DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                 self?.performAiTurn()
             }
         }
    }

    // --- Styling Functions ---
    func setupMainBackground() { backgroundGradientLayer?.removeFromSuperlayer(); let gradient = CAGradientLayer(); gradient.frame = self.view.bounds; let topColor = UIColor(red: 0.96, green: 0.97, blue: 0.98, alpha: 1.0).cgColor; let bottomColor = UIColor(red: 0.91, green: 0.92, blue: 0.93, alpha: 1.0).cgColor; gradient.colors = [topColor, bottomColor]; gradient.startPoint = CGPoint(x: 0.5, y: 0.0); gradient.endPoint = CGPoint(x: 0.5, y: 1.0); self.view.layer.insertSublayer(gradient, at: 0); self.backgroundGradientLayer = gradient }
    func styleResetButton() {
        guard let button = resetButton else { return }
        print("Styling Reset Button (V3 - with Icon)...")
        if #available(iOS 15.0, *) {
            var config = UIButton.Configuration.filled(); config.title = "Reset Game"; config.attributedTitle?.font = UIFont.systemFont(ofSize: 16, weight: .semibold); config.image = UIImage(systemName: "arrow.counterclockwise.circle"); config.imagePadding = 8; config.imagePlacement = .leading; config.baseBackgroundColor = UIColor(red: 0.90, green: 0.91, blue: 0.93, alpha: 1.0); config.baseForegroundColor = UIColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1.0); config.cornerStyle = .medium; config.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 18, bottom: 10, trailing: 18); button.configuration = config; button.layer.shadowColor = UIColor.black.cgColor; button.layer.shadowOffset = CGSize(width: 0, height: 1); button.layer.shadowRadius = 2.5; button.layer.shadowOpacity = 0.12; button.layer.masksToBounds = false
        } else {
            let buttonBackgroundColor = UIColor(red: 0.95, green: 0.95, blue: 0.97, alpha: 1.0); let buttonTextColor = UIColor(red: 0.2, green: 0.2, blue: 0.2, alpha: 1.0); let buttonBorderColor = UIColor(red: 0.75, green: 0.75, blue: 0.75, alpha: 0.8); button.backgroundColor = buttonBackgroundColor; button.setTitleColor(buttonTextColor, for: .normal); button.setTitleColor(buttonTextColor.withAlphaComponent(0.5), for: .highlighted); button.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .semibold); button.layer.cornerRadius = 8; button.layer.borderWidth = 0.75; button.layer.borderColor = buttonBorderColor.cgColor; button.layer.shadowColor = UIColor.black.cgColor; button.layer.shadowOffset = CGSize(width: 0, height: 1); button.layer.shadowRadius = 2.5; button.layer.shadowOpacity = 0.12; button.layer.masksToBounds = false; button.contentEdgeInsets = UIEdgeInsets(top: 10, left: 20, bottom: 10, right: 20)
        }
        print("Reset Button styling applied (V3).")
    }
    func styleStatusLabel() { guard let label = statusLabel else { return }; label.font = UIFont.systemFont(ofSize: 22, weight: .medium); label.textColor = UIColor(red: 0.15, green: 0.15, blue: 0.15, alpha: 1.0); label.textAlignment = .center; label.layer.shadowColor = UIColor.black.cgColor; label.layer.shadowOffset = CGSize(width: 0, height: 1); label.layer.shadowRadius = 2.0; label.layer.shadowOpacity = 0.1; label.layer.masksToBounds = false }

    // --- Drawing Functions ---
    func drawProceduralWoodBackground() { woodBackgroundLayers.forEach { $0.removeFromSuperlayer() }; woodBackgroundLayers.removeAll(); guard boardView.bounds.width > 0 && boardView.bounds.height > 0 else { print("Skipping wood background draw: boardView bounds not ready."); return }; print("Drawing procedural wood background into bounds: \(boardView.bounds)"); let baseLayer = CALayer(); baseLayer.frame = boardView.bounds; baseLayer.backgroundColor = UIColor(red: 0.65, green: 0.50, blue: 0.35, alpha: 1.0).cgColor; baseLayer.cornerRadius = boardView.layer.cornerRadius; baseLayer.masksToBounds = true; boardView.layer.insertSublayer(baseLayer, at: 0); woodBackgroundLayers.append(baseLayer); let grainLayerCount = 35; let boardWidth = boardView.bounds.width; let boardHeight = boardView.bounds.height; for _ in 0..<grainLayerCount { let grainLayer = CALayer(); let randomDarkness = CGFloat.random(in: -0.10...0.15); let baseRed: CGFloat = 0.65; let baseGreen: CGFloat = 0.50; let baseBlue: CGFloat = 0.35; let grainColor = UIColor(red: max(0.1, min(0.9, baseRed + randomDarkness)), green: max(0.1, min(0.9, baseGreen + randomDarkness)), blue: max(0.1, min(0.9, baseBlue + randomDarkness)), alpha: CGFloat.random(in: 0.1...0.35)); grainLayer.backgroundColor = grainColor.cgColor; let grainWidth = CGFloat.random(in: 1.5...4.0); let grainX = CGFloat.random(in: 0...(boardWidth - grainWidth)); grainLayer.frame = CGRect(x: grainX, y: 0, width: grainWidth, height: boardHeight); baseLayer.addSublayer(grainLayer) }; let lightingGradient = CAGradientLayer(); lightingGradient.frame = boardView.bounds; lightingGradient.cornerRadius = baseLayer.cornerRadius; lightingGradient.type = .radial; lightingGradient.colors = [UIColor(white: 1.0, alpha: 0.15).cgColor, UIColor(white: 1.0, alpha: 0.0).cgColor, UIColor(white: 0.0, alpha: 0.15).cgColor]; lightingGradient.locations = [0.0, 0.6, 1.0]; lightingGradient.startPoint = CGPoint(x: 0.5, y: 0.5); lightingGradient.endPoint = CGPoint(x: 1.0, y: 1.0); baseLayer.addSublayer(lightingGradient); baseLayer.borderWidth = 2.0; baseLayer.borderColor = UIColor(white: 0.1, alpha: 0.8).cgColor }
    func drawBoard() { boardView.layer.sublayers?.filter { $0.name == "gridLine" }.forEach { $0.removeFromSuperlayer() }; guard cellSize > 0 else { print("Skipping drawBoard: cellSize is 0"); return }; guard woodBackgroundLayers.first != nil else { print("Cannot draw board: Wood background layer not found."); return }; let boardDimension = cellSize * CGFloat(boardSize - 1); let gridLineColor = UIColor(white: 0.1, alpha: 0.65).cgColor; let gridLineWidth: CGFloat = 0.75; for i in 0..<boardSize { let vLayer = CALayer(); let xPos = boardPadding + CGFloat(i) * cellSize; vLayer.frame = CGRect(x: xPos - (gridLineWidth / 2), y: boardPadding, width: gridLineWidth, height: boardDimension); vLayer.backgroundColor = gridLineColor; vLayer.name = "gridLine"; boardView.layer.addSublayer(vLayer); let hLayer = CALayer(); let yPos = boardPadding + CGFloat(i) * cellSize; hLayer.frame = CGRect(x: boardPadding, y: yPos - (gridLineWidth / 2), width: boardDimension, height: gridLineWidth); hLayer.backgroundColor = gridLineColor; hLayer.name = "gridLine"; boardView.layer.addSublayer(hLayer) }; print("Board drawn with cell size: \(cellSize)") }
    func redrawPieces() { guard cellSize > 0 else { print("Skipping redrawPieces: cellSize is 0"); return }; boardView.subviews.forEach { $0.removeFromSuperview() }; pieceViews = Array(repeating: Array(repeating: nil, count: boardSize), count: boardSize); for r in 0..<boardSize { for c in 0..<boardSize { let cellState = board[r][c]; if cellState == .black || cellState == .white { drawPiece(atRow: r, col: c, player: (cellState == .black) ? .black : .white, animate: false) /* No animation on redraw */ }}} } // Add animate flag
    
    // Modified drawPiece to optionally skip animation (useful for redraws)
    func drawPiece(atRow row: Int, col: Int, player: Player, animate: Bool = true) {
        guard cellSize > 0 else { return }
        let pieceSize = cellSize * 0.85; let x = boardPadding + CGFloat(col) * cellSize - (pieceSize / 2); let y = boardPadding + CGFloat(row) * cellSize - (pieceSize / 2); let pieceFrame = CGRect(x: x, y: y, width: pieceSize, height: pieceSize)
        let pieceView = UIView(frame: pieceFrame); pieceView.backgroundColor = .clear

        let gradientLayer = CAGradientLayer(); gradientLayer.frame = pieceView.bounds; gradientLayer.cornerRadius = pieceSize / 2; gradientLayer.type = .radial
        let lightColor: UIColor; let darkColor: UIColor; let highlightColor: UIColor
        if player == .black { highlightColor = UIColor(white: 0.5, alpha: 1.0); lightColor = UIColor(white: 0.3, alpha: 1.0); darkColor = UIColor(white: 0.05, alpha: 1.0) }
        else { highlightColor = UIColor(white: 1.0, alpha: 1.0); lightColor = UIColor(white: 0.95, alpha: 1.0); darkColor = UIColor(white: 0.75, alpha: 1.0) }
        gradientLayer.colors = [highlightColor.cgColor, lightColor.cgColor, darkColor.cgColor]; gradientLayer.locations = [0.0, 0.15, 1.0]; gradientLayer.startPoint = CGPoint(x: 0.25, y: 0.25); gradientLayer.endPoint = CGPoint(x: 0.75, y: 0.75)

        pieceView.layer.addSublayer(gradientLayer); pieceView.layer.cornerRadius = pieceSize / 2; pieceView.layer.borderWidth = 0.5
        pieceView.layer.borderColor = (player == .black) ? UIColor(white: 0.5, alpha: 0.7).cgColor : UIColor(white: 0.6, alpha: 0.7).cgColor
        pieceView.layer.shadowColor = UIColor.black.cgColor; pieceView.layer.shadowOpacity = 0.4; pieceView.layer.shadowOffset = CGSize(width: 1, height: 2); pieceView.layer.shadowRadius = 2.0; pieceView.layer.masksToBounds = false

        // Ensure removal happens *before* adding subview
        pieceViews[row][col]?.removeFromSuperview()
        boardView.addSubview(pieceView)
        pieceViews[row][col] = pieceView // Update reference

        if animate {
            pieceView.alpha = 0.0; pieceView.transform = CGAffineTransform(scaleX: 0.6, y: 0.6)
            UIView.animate(withDuration: 0.25, delay: 0, usingSpringWithDamping: 0.6, initialSpringVelocity: 0.5, options: .curveEaseOut, animations: {
                pieceView.alpha = 1.0; pieceView.transform = .identity
            }, completion: nil)
        } else {
            pieceView.alpha = 1.0
            pieceView.transform = .identity
        }
    }
    
    // --- Last Move Indicator ---
    // Modified to handle removal/recreation better on layout changes
    func showLastMoveIndicator(at position: Position) {
        // Remove previous indicator layer immediately
        lastMoveIndicatorLayer?.removeFromSuperlayer()
        lastMoveIndicatorLayer = nil

        guard cellSize > 0, !gameOver else { return } // Don't show if game over or cellsize invalid

        let indicatorSize = cellSize * 0.95 // Slightly larger than piece
        let x = boardPadding + CGFloat(position.col) * cellSize - (indicatorSize / 2)
        let y = boardPadding + CGFloat(position.row) * cellSize - (indicatorSize / 2)
        let indicatorFrame = CGRect(x: x, y: y, width: indicatorSize, height: indicatorSize)

        let indicator = CALayer()
        indicator.frame = indicatorFrame
        indicator.cornerRadius = indicatorSize / 2
        indicator.borderWidth = 2.5 // Thicker border for indicator
        indicator.borderColor = UIColor.systemYellow.withAlphaComponent(0.8).cgColor // Yellowish indicator
        indicator.opacity = 0.0 // Start invisible
        indicator.name = "lastMoveIndicator" // Give it a name

        // Ensure it's drawn above grid lines but below pieces (if needed)
        // Adding directly to boardView.layer usually puts it above CALayers but below UIViews
        boardView.layer.addSublayer(indicator)
        self.lastMoveIndicatorLayer = indicator

        // Fade In Animation
        let fadeIn = CABasicAnimation(keyPath: "opacity")
        fadeIn.fromValue = 0.0; fadeIn.toValue = 0.8; fadeIn.duration = 0.2

        // Apply fade-in
        indicator.opacity = 0.8 // Set final opacity for fade in
        indicator.add(fadeIn, forKey: "fadeInIndicator")

        // --- Simpler Removal Logic ---
        // The indicator is now simply replaced next time showLastMoveIndicator is called,
        // or removed explicitly on game over or reset. No complex fade-out needed here.
    }

    // --- Game Logic & Interaction ---
    func setupNewGameVariablesOnly() { currentPlayer = .black; board = Array(repeating: Array(repeating: .empty, count: boardSize), count: boardSize); gameOver = false; pieceViews = Array(repeating: Array(repeating: nil, count: boardSize), count: boardSize); lastWinningPositions = nil } // Reset win line state
    func setupNewGame() {
        print("setupNewGame called. Current Mode: \(currentGameMode)");
        gameOver = false; currentPlayer = .black; statusLabel.text = "Black's Turn"; board = Array(repeating: Array(repeating: .empty, count: boardSize), count: boardSize);

        // Clear visual elements
        boardView.subviews.forEach { $0.removeFromSuperview() }; // Removes piece UIViews
        // Remove specific layers by name - safer than removing all
        boardView.layer.sublayers?.filter { $0.name == "gridLine" || $0.name == "winningLine" || $0.name == "lastMoveIndicator"}.forEach { $0.removeFromSuperlayer() };
        woodBackgroundLayers.forEach { $0.removeFromSuperlayer() }; woodBackgroundLayers.removeAll();
        winningLineLayer = nil; lastMoveIndicatorLayer = nil; lastMovePosition = nil; lastWinningPositions = nil

        pieceViews = Array(repeating: Array(repeating: nil, count: boardSize), count: boardSize);

        // --- FIX: Reset layout dependent variables ---
        cellSize = 0 // CRITICAL: Force redraw in viewDidLayoutSubviews
        lastDrawnBoardBounds = .zero // Also reset bounds to be absolutely sure redraw happens

        if turnIndicatorBorderLayer == nil { setupTurnIndicatorBorder() } // Create if first game
        updateTurnIndicator() // Set color for Black's turn
        updateTurnIndicatorLine()
        turnIndicatorBorderLayer?.isHidden = false // Ensure visible
        turnIndicatorView?.isHidden = false      // Ensure visible

        print("setupNewGame: Reset game state. Requesting layout update.")
        // Request layout update, which will trigger viewDidLayoutSubviews
        view.setNeedsLayout()
        // Optionally, force layout immediately if needed, but setNeedsLayout should suffice
        // view.layoutIfNeeded()
    }
    func calculateCellSize() -> CGFloat { guard boardView.bounds.width > 0, boardView.bounds.height > 0 else { return 0 }; let boardDimension = min(boardView.bounds.width, boardView.bounds.height) - (boardPadding * 2); guard boardSize > 1 else { return boardDimension }; let size = boardDimension / CGFloat(boardSize - 1); return max(0, size) }
    func addTapGestureRecognizer() { guard let currentBoardView = boardView else { print("FATAL ERROR: boardView outlet is NIL..."); return }; /* print("addTapGestureRecognizer attempting to add..."); */ currentBoardView.gestureRecognizers?.forEach { currentBoardView.removeGestureRecognizer($0) }; let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:))); currentBoardView.addGestureRecognizer(tap); /* print("--> Tap Gesture Recognizer ADDED.") */ }
    
    func shakeBoard() {
        print("Shaking board for invalid move")
        if shakeAnimation == nil {
            let animation = CABasicAnimation(keyPath: "position.x"); animation.duration = 0.07; animation.repeatCount = 3; animation.autoreverses = true; animation.fromValue = NSNumber(value: boardView.center.x - CGFloat(6)); animation.toValue = NSNumber(value: boardView.center.x + CGFloat(6)); shakeAnimation = animation
        }
        if let shake = shakeAnimation, boardView != nil { boardView.layer.add(shake, forKey: "position.x") }
        else if boardView == nil { print("Warning: Tried to shake boardView but it was nil.") }
    }
    
    @objc func handleTap(_ sender: UITapGestureRecognizer) {
        guard currentGameState == .playing else { return }
        // print("--- handleTap CALLED ---")
        guard !gameOver, cellSize > 0 else { return }
        guard !isAiTurn else { print("Tap ignored: It's AI's turn."); return } // Prevent human playing on AI turn
        let location = sender.location(in: boardView)
        let playableWidth = cellSize * CGFloat(boardSize - 1); let playableHeight = cellSize * CGFloat(boardSize - 1)
        // More precise tap area calculation centered on grid lines
        let tapArea = CGRect(x: boardPadding - cellSize * 0.5, y: boardPadding - cellSize * 0.5,
                             width: playableWidth + cellSize, height: playableHeight + cellSize)

        guard tapArea.contains(location) else { print("Tap outside playable area."); shakeBoard(); return }

        // Calculate nearest intersection
        let tappedColFloat = (location.x - boardPadding + cellSize * 0.5) / cellSize
        let tappedRowFloat = (location.y - boardPadding + cellSize * 0.5) / cellSize
        let tappedCol = Int(floor(tappedColFloat))
        let tappedRow = Int(floor(tappedRowFloat))

        // print("Rounded integer coords: (col: \(tappedCol), row: \(tappedRow))")
        guard checkBounds(row: tappedRow, col: tappedCol) else { print("Tap out of bounds."); shakeBoard(); return }
        guard board[tappedRow][tappedCol] == .empty else { print("Cell already occupied."); shakeBoard(); return }

        print("Human placing piece at (\(tappedRow), \(tappedCol))"); placePiece(atRow: tappedRow, col: tappedCol)
    }
    
    func placePiece(atRow row: Int, col: Int) {
        guard currentGameState == .playing, !gameOver else { return }
        guard checkBounds(row: row, col: col) && board[row][col] == .empty else {
             print("Error: Attempted to place piece in invalid or occupied cell (\(row), \(col)). Current state: \(board[row][col])")
             // Potentially trigger AI again if this was called erroneously by AI? Or just return.
             if isAiTurn { // If AI made an invalid move, try again? Risky, could loop. Log error.
                 print("!!! AI ERROR: AI attempted invalid move. Halting AI turn. !!!")
                 view.isUserInteractionEnabled = true // Give control back?
             }
             return
        }

        let pieceState: CellState = (currentPlayer == .black) ? .black : .white; board[row][col] = pieceState

        // Draw the piece (with animation)
        drawPiece(atRow: row, col: col, player: currentPlayer, animate: true)

        let currentPosition = Position(row: row, col: col)
        self.lastMovePosition = currentPosition // Store position
        // Delay showing indicator slightly to let piece animation start
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.showLastMoveIndicator(at: currentPosition)
        }

        if let winningPositions = findWinningLine(playerState: pieceState, lastRow: row, lastCol: col) {
            gameOver = true; self.lastWinningPositions = winningPositions // Store for redraws
            updateTurnIndicator(); updateTurnIndicatorLine()
            let winner = (pieceState == .black) ? "Black" : "White"; let message = "\(winner) Wins!"
            statusLabel.text = message; print(message); drawWinningLine(positions: winningPositions)
            showGameOverOverlay(message: message); view.isUserInteractionEnabled = true
            lastMoveIndicatorLayer?.removeFromSuperlayer() // Remove indicator immediately on win
            lastMoveIndicatorLayer = nil
        } else if isBoardFull() {
            gameOver = true; updateTurnIndicator(); updateTurnIndicatorLine(); statusLabel.text = "Draw!"; print("Draw!")
            showGameOverOverlay(message: "Draw!"); view.isUserInteractionEnabled = true
            lastMoveIndicatorLayer?.removeFromSuperlayer() // Remove indicator immediately on draw
            lastMoveIndicatorLayer = nil
        } else {
            switchPlayer() // Only switch if game not over
        }
    }
    
    func findWinningLine(playerState: CellState, lastRow: Int, lastCol: Int) -> [Position]? {
        guard playerState != .empty else { return nil }; let directions = [(0, 1), (1, 0), (1, 1), (1, -1)]; for (dr, dc) in directions { var linePositions: [Position] = [Position(row: lastRow, col: lastCol)]; var count = 1
            // Check positive direction
            for i in 1..<5 { let r = lastRow + dr * i; let c = lastCol + dc * i; if checkBounds(row: r, col: c) && board[r][c] == playerState { linePositions.append(Position(row: r, col: c)); count += 1 } else { break } }
            // Check negative direction
            for i in 1..<5 { let r = lastRow - dr * i; let c = lastCol - dc * i; if checkBounds(row: r, col: c) && board[r][c] == playerState { linePositions.append(Position(row: r, col: c)); count += 1 } else { break } }
            if count >= 5 { linePositions.sort { ($0.row, $0.col) < ($1.row, $1.col) }; return Array(linePositions) /* Return the actual line */ } }; return nil
    } // Return actual winning line positions

    func switchPlayer() {
        guard !gameOver else { return };
        // let previousPlayer = currentPlayer; // Keep for potential debugging
        currentPlayer = (currentPlayer == .black) ? .white : .black;
        statusLabel.text = "\(currentPlayer == .black ? "Black" : "White")'s Turn";
        updateTurnIndicator(); updateTurnIndicatorLine();

        if isAiTurn {
            view.isUserInteractionEnabled = false; // Disable human input
            statusLabel.text = "Computer (\(selectedDifficulty)) Turn...";
            print("Switching to AI (\(selectedDifficulty)) turn...");
            // Add delay for AI 'thinking' time and visual pacing
            let delay = (selectedDifficulty == .hard) ? 0.6 : 0.4 // Slightly longer delay for hard AI
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                 guard let self = self else { return };
                 // Double-check game state before AI moves
                 if !self.gameOver && self.isAiTurn {
                     self.performAiTurn()
                 } else {
                      print("AI turn skipped (game over or state changed during delay)");
                      if !self.gameOver { self.view.isUserInteractionEnabled = true } // Re-enable if game not over
                 }
            }
        } else {
            print("Switching to Human turn...");
            view.isUserInteractionEnabled = true // Ensure human input is enabled
        }
    }

    // --- REMOVE OLD AI HELPERS ---
    // func findMakeFourMove(...) - Removed
    // func findSpecificOpenThreeMove(...) - Removed
    // func findMakeTwoMove(...) - Removed (Now part of Easy/Medium logic, Hard doesn't need it directly)
    // func checkPattern(...) - Removed (Replaced by logic within createsThreat)

    // --- AI Logic ---
    func performAiTurn() {
       guard !gameOver else { view.isUserInteractionEnabled = true; return } // Safety check
       print("AI Turn (\(selectedDifficulty)): Performing move...")
       let startTime = CFAbsoluteTimeGetCurrent()

       switch selectedDifficulty {
           case .easy: performSimpleAiMove()
           case .medium: performStandardAiMove()
           case .hard: performHardAiMove() // Calls the NEW Hard AI logic
       }

       let timeElapsed = CFAbsoluteTimeGetCurrent() - startTime
       print("AI (\(selectedDifficulty)) took \(String(format: "%.3f", timeElapsed)) seconds.")

       // Re-enable user interaction *after* the AI move is placed and processed by placePiece->switchPlayer
       // This is handled within switchPlayer now if the next turn is Human's.
       // If game ends on AI turn, showGameOverOverlay enables interaction.
       DispatchQueue.main.async { // Ensure UI updates happen on main thread
            if !self.gameOver && !self.isAiTurn { // If it's now human's turn
                self.view.isUserInteractionEnabled = true
                self.statusLabel.text = "\(self.currentPlayer == .black ? "Black" : "White")'s Turn"; // Update label correctly
                print("AI Turn (\(self.selectedDifficulty)): Completed. Re-enabled user interaction.")
            } else if self.gameOver {
                // Interaction enabled by showGameOverOverlay
                print("AI Turn (\(self.selectedDifficulty)): Game Over.")
            } else {
                // Should not happen unless AI plays against AI
                 print("AI Turn (\(self.selectedDifficulty)): Completed, still AI turn? (AI vs AI?)")
            }
       }
   }

    // RENAME performEasyAiMove -> performSimpleAiMove (Logic Unchanged)
    func performSimpleAiMove() {
        let emptyCells = findEmptyCells(); if emptyCells.isEmpty { print("AI Easy: No empty cells left."); return }; let humanPlayer: Player = opponent(of: aiPlayer);
        // 1. Win?
        for cell in emptyCells { if checkPotentialWin(player: aiPlayer, position: cell) { print("AI Easy: Found winning move at \(cell)"); placeAiPieceAndEndTurn(at: cell); return } };
        // 2. Block Win?
        for cell in emptyCells { if checkPotentialWin(player: humanPlayer, position: cell) { print("AI Easy: Found blocking move at \(cell)"); placeAiPieceAndEndTurn(at: cell); return } };
        // 3. Random Adjacent?
        let adjacentCells = findAdjacentEmptyCells(); if let targetCell = adjacentCells.randomElement() { print("AI Easy: Playing random adjacent move at \(targetCell)"); placeAiPieceAndEndTurn(at: targetCell); return };
        // 4. Completely Random?
        if let targetCell = emptyCells.randomElement() { print("AI Easy: Playing completely random move at \(targetCell)"); placeAiPieceAndEndTurn(at: targetCell); return };
        print("AI Easy: Could not find any valid move.") // Should be unreachable if emptyCells not empty
    }

    // RENAME performMediumAiMove -> performStandardAiMove (Simplified using new helpers)
    func performStandardAiMove() {
         let emptyCells = findEmptyCells(); if emptyCells.isEmpty { print("AI Medium: No empty cells left."); return }; let humanPlayer: Player = opponent(of: aiPlayer);

         // 1. Win?
         if let winMove = findMovesCreatingThreat(player: aiPlayer, threat: .five, emptyCells: emptyCells).first { print("AI Medium: Found winning move at \(winMove)"); placeAiPieceAndEndTurn(at: winMove); return }
         // 2. Block Win?
         if let blockMove = findMovesCreatingThreat(player: humanPlayer, threat: .five, emptyCells: emptyCells).first { print("AI Medium: Found blocking win move at \(blockMove)"); placeAiPieceAndEndTurn(at: blockMove); return }
         // 3. Create Open Three?
         if let createMove = findMovesCreatingThreat(player: aiPlayer, threat: .openThree, emptyCells: emptyCells).first { print("AI Medium: Found creating Open Three move at \(createMove)"); placeAiPieceAndEndTurn(at: createMove); return }
         // 4. Block Open Three?
         if let blockMove = findMovesCreatingThreat(player: humanPlayer, threat: .openThree, emptyCells: emptyCells).first { print("AI Medium: Found blocking Open Three move at \(blockMove)"); placeAiPieceAndEndTurn(at: blockMove); return }
        // 5. Create Closed Three? (Lower priority)
        if let createMove = findMovesCreatingThreat(player: aiPlayer, threat: .closedThree, emptyCells: emptyCells).first { print("AI Medium: Found creating Closed Three move at \(createMove)"); placeAiPieceAndEndTurn(at: createMove); return }
        // 6. Block Closed Three?
        if let blockMove = findMovesCreatingThreat(player: humanPlayer, threat: .closedThree, emptyCells: emptyCells).first { print("AI Medium: Found blocking Closed Three move at \(blockMove)"); placeAiPieceAndEndTurn(at: blockMove); return }

         // 7. Fallback to Simple AI (Adjacent/Random)
         print("AI Medium: No better move found. Falling back to Simple logic.");
         performSimpleAiMove()
    }


    // --- NEW HARD AI LOGIC ---
    func performHardAiMove() {
        let emptyCells = findEmptyCells()
        guard !emptyCells.isEmpty else { print("AI Hard: No empty cells left."); return }
        let humanPlayer: Player = opponent(of: aiPlayer)

        // Handle first move (play near center)
        let totalPieces = board.flatMap({ $0 }).filter({ $0 != .empty }).count
        if totalPieces < 2 {
            let center = boardSize / 2
            let centerPos = Position(row: center, col: center)
            var move: Position? = nil
            if checkBounds(row: center, col: center) && board[center][center] == .empty {
                 move = centerPos
                 print("AI Hard: First move, playing center.")
            } else {
                 // If center taken, play adjacent randomly (prefer corners/edges of center 3x3)
                 let preferredAdjacent = emptyCells.filter { p in
                     max(abs(p.row - center), abs(p.col - center)) <= 1 && // 3x3 around center
                     (abs(p.row - center) == 1 || abs(p.col - center) == 1) // Exclude center itself if already checked
                 }
                 move = preferredAdjacent.randomElement() ?? findAdjacentEmptyCells().randomElement() ?? emptyCells.randomElement()
                 print("AI Hard: First move, center taken, playing near center.")
            }
            if let firstMove = move {
                 placeAiPieceAndEndTurn(at: firstMove); return
            }
        }

        print("AI Hard: Evaluating moves...")

        // --- AI Priorities ---

        // 1. Win? (AI immediate Five)
        if let winMove = findMovesCreatingThreat(player: aiPlayer, threat: .five, emptyCells: emptyCells).first {
            print("AI Hard (P1): Found winning move at \(winMove)")
            placeAiPieceAndEndTurn(at: winMove); return
        }

        // 2. Block Win? (Human immediate Five)
        let blockWinMoves = findMovesCreatingThreat(player: humanPlayer, threat: .five, emptyCells: emptyCells)
        if let blockMove = blockWinMoves.first { // Block the first one found (usually only one)
            print("AI Hard (P2): Found blocking win move at \(blockMove)")
            placeAiPieceAndEndTurn(at: blockMove); return
        }
         // Handle rare case of multiple simultaneous win threats (e.g., human creates two lines of 4) - Block one
         if blockWinMoves.count > 1, let multiBlockMove = blockWinMoves.randomElement() {
             print("AI Hard (P2b): Found MULTIPLE blocking win moves! Blocking one at \(multiBlockMove)")
             placeAiPieceAndEndTurn(at: multiBlockMove); return
         }


        // 3. Create AI Open Four?
        if let openFourMove = findMovesCreatingThreat(player: aiPlayer, threat: .openFour, emptyCells: emptyCells).first {
            print("AI Hard (P3): Found creating Open Four move at \(openFourMove)")
            placeAiPieceAndEndTurn(at: openFourMove); return
        }

        // 4. Block Human Open Four? (This is a critical defensive move)
        let humanOpenFourBlocks = findMovesCreatingThreat(player: humanPlayer, threat: .openFour, emptyCells: emptyCells)
        // If human has multiple open fours, AI needs to block one. But which one?
        // A simple strategy is block the first. A better one might evaluate which block also helps AI.
        // For now, just block the first one found.
        if let blockHumanOpenFour = humanOpenFourBlocks.first {
             print("AI Hard (P4): Blocking opponent's Open Four at \(blockHumanOpenFour)")
             placeAiPieceAndEndTurn(at: blockHumanOpenFour); return
        }
         // Handle multiple open four threats from human (less common but possible)
         if humanOpenFourBlocks.count > 1, let multiBlockOpenFour = humanOpenFourBlocks.randomElement() {
             print("AI Hard (P4b): Found MULTIPLE opponent Open Fours! Blocking one at \(multiBlockOpenFour)")
             placeAiPieceAndEndTurn(at: multiBlockOpenFour); return
         }


        // 5. Combined Threat Analysis (Middle Priority)
        // Find all potential moves for mid-level threats (for both players)
        let aiClosedFourMoves = findMovesCreatingThreat(player: aiPlayer, threat: .closedFour, emptyCells: emptyCells)
        let aiOpenThreeMoves = findMovesCreatingThreat(player: aiPlayer, threat: .openThree, emptyCells: emptyCells)
        let humanClosedFourBlocks = findMovesCreatingThreat(player: humanPlayer, threat: .closedFour, emptyCells: emptyCells)
        let humanOpenThreeBlocks = findMovesCreatingThreat(player: humanPlayer, threat: .openThree, emptyCells: emptyCells)

        // Assign priorities/scores to potential moves
        var candidateMoves: [Position: Int] = [:] // Position -> Score/Priority

        // Higher score is better. Offensive moves prioritized slightly over equivalent blocks.
        for move in aiClosedFourMoves { candidateMoves[move] = (candidateMoves[move] ?? 0) + 450 } // Slightly > block open three
        for move in aiOpenThreeMoves { candidateMoves[move] = (candidateMoves[move] ?? 0) + 400 } // Strong setup

        // Defensive moves (blocking opponent) - Add score to the blocking position
        for move in humanClosedFourBlocks { candidateMoves[move] = (candidateMoves[move] ?? 0) + 100 } // Block forcing move
        for move in humanOpenThreeBlocks { candidateMoves[move] = (candidateMoves[move] ?? 0) + 350 } // Block strong setup (slightly less than creating own open three)

        // Add a small bonus for moves that create multiple threats (e.g., an open three AND block an open three)
        // This requires a more complex evaluation, skipping for now for simplicity.

        // Sort candidates by score (descending)
        let sortedCandidates = candidateMoves.keys.sorted { (candidateMoves[$0] ?? 0) > (candidateMoves[$1] ?? 0) }

        if let bestThreatMove = sortedCandidates.first {
             let score = candidateMoves[bestThreatMove] ?? 0
             print("AI Hard (P5): Playing threat-based move (Score \(score)) at \(bestThreatMove)")
             placeAiPieceAndEndTurn(at: bestThreatMove); return
        }


        // 6. Center/Adjacent Preference Fallback (Development Moves)
        let adjacentCells = findAdjacentEmptyCells()
        var preferredMoves: [Position] = []
        let center = boardSize / 2
        let maxDist = boardSize / 3 // Define a 'near center' radius

        // Prioritize adjacent cells near the center
        for cell in adjacentCells {
            let distFromCenter = max(abs(cell.row - center), abs(cell.col - center))
            if distFromCenter <= maxDist { preferredMoves.append(cell) }
        }
        // If no adjacent near center, take any adjacent
        if preferredMoves.isEmpty && !adjacentCells.isEmpty { preferredMoves = adjacentCells }
        // If still no preferred moves (e.g., board sparse), consider any non-adjacent cell near center
        if preferredMoves.isEmpty {
            for cell in emptyCells {
                 if !adjacentCells.contains(cell) { // Only non-adjacent
                      let distFromCenter = max(abs(cell.row - center), abs(cell.col - center))
                      if distFromCenter <= maxDist { preferredMoves.append(cell) }
                 }
            }
        }

        if let preferredMove = preferredMoves.randomElement() {
            print("AI Hard (P6): Playing preferred adjacent/center move at \(preferredMove)")
            placeAiPieceAndEndTurn(at: preferredMove); return
        }

        // 7. Fallback to completely random empty cell if absolutely nothing else found
        if let randomMove = emptyCells.randomElement() {
            print("AI Hard (P7): No better move found. Playing random move at \(randomMove)")
            placeAiPieceAndEndTurn(at: randomMove); return
        }

        print("AI Hard: Could not find ANY valid move (Error state).")
        // As a last resort, maybe just let the turn pass back? Or try simple AI again?
        view.isUserInteractionEnabled = true // Failsafe
    }


    // --- Hard AI Helper Enums and Functions ---

    enum ThreatType: Int {
        case five = 10000      // Immediate Win
        case openFour = 5000   // Guarantees win next turn if not blocked at both ends (usually impossible)
        case closedFour = 450  // Forcing move, but less guaranteed win than open four
        case openThree = 400   // Strong setup, usually leads to open four or win
        case closedThree = 50  // Weaker setup, less forcing
    }

    // Function to find empty cells where placing a piece *creates* the specified threat
    func findMovesCreatingThreat(player: Player, threat: ThreatType, emptyCells: [Position]) -> [Position] {
        var threatMoves: [Position] = []
        // let playerState = state(for: player) // Not needed directly here

        for position in emptyCells {
            // Temporarily place piece and check if the *resulting board state* contains the threat pattern originating from 'position'
            var tempBoard = self.board
            tempBoard[position.row][position.col] = state(for: player) // Place piece

            if checkForThreatOnBoard(boardToCheck: tempBoard, player: player, threat: threat, lastMove: position) {
                 threatMoves.append(position)
            }
        }
        return threatMoves
    }

    // Checks the board *after* a move has been made at lastMove for the specified threat type involving that last move
    func checkForThreatOnBoard(boardToCheck: [[CellState]], player: Player, threat: ThreatType, lastMove: Position) -> Bool {
        let playerState = state(for: player)
        let opponentState = state(for: opponent(of: player))
        let directions = [(0, 1), (1, 0), (1, 1), (1, -1)] // Horizontal, Vertical, Diag Down, Diag Up

        for (dr, dc) in directions {
            // --- Check patterns centered around lastMove ---
            // Use sliding windows of 5 or 6 cells along the direction

            // FIVE: Check existing win condition checker
            if threat == .five {
                 if checkForWinOnBoard(boardToCheck: boardToCheck, playerState: playerState, lastRow: lastMove.row, lastCol: lastMove.col) {
                     return true
                 }
                 continue // Check next direction
            }

            // FOURS (Check window 6: EPPPPE)
            if threat == .openFour {
                 for offset in -5...0 { // Start checking from 5 steps before to include all 6-windows containing the new piece
                     let r = lastMove.row + dr * offset
                     let c = lastMove.col + dc * offset
                     // Check bounds for the 6-window
                     guard checkBounds(row: r, col: c) && checkBounds(row: r + dr * 5, col: c + dc * 5) else { continue }

                     if boardToCheck[r][c] == .empty &&
                        boardToCheck[r+dr][c+dc] == playerState &&
                        boardToCheck[r+dr*2][c+dc*2] == playerState &&
                        boardToCheck[r+dr*3][c+dc*3] == playerState &&
                        boardToCheck[r+dr*4][c+dc*4] == playerState &&
                        boardToCheck[r+dr*5][c+dc*5] == .empty {
                           return true // Found Open Four
                     }
                 }
            }

            // THREES and CLOSED FOURS (Check window 5 and context)
            if threat == .closedFour || threat == .openThree || threat == .closedThree {
                 for offset in -4...0 { // Check 5-windows containing the new piece
                     let r = lastMove.row + dr * offset
                     let c = lastMove.col + dc * offset
                     // Check bounds for the 5-window
                     guard checkBounds(row: r, col: c) && checkBounds(row: r + dr * 4, col: c + dc * 4) else { continue }

                     var pCount = 0
                     var eCount = 0
                     var window5: [CellState] = []
                     for i in 0..<5 {
                          let cellState = boardToCheck[r+dr*i][c+dc*i]
                          window5.append(cellState)
                          if cellState == playerState { pCount += 1 }
                          else if cellState == .empty { eCount += 1 }
                     }

                     // Check context cells (before start, after end)
                     let rBefore = r - dr
                     let cBefore = c - dc
                     let rAfter = r + dr * 5
                     let cAfter = c + dc * 5

                     let stateBefore = checkBounds(row: rBefore, col: cBefore) ? boardToCheck[rBefore][cBefore] : opponentState // Treat out of bounds as opponent blockage
                     let stateAfter = checkBounds(row: rAfter, col: cAfter) ? boardToCheck[rAfter][cAfter] : opponentState // Treat out of bounds as opponent blockage

                     let isOpenBefore = stateBefore == .empty
                     let isOpenAfter = stateAfter == .empty
                     let isBlockedBefore = !isOpenBefore // Blocked by opponent or edge
                     let isBlockedAfter = !isOpenAfter  // Blocked by opponent or edge

                     // --- Match Threat Type ---
                     if threat == .closedFour && pCount == 4 && eCount == 1 {
                          // Need exactly one side blocked, one empty
                          if (isBlockedBefore && isOpenAfter) || (isOpenBefore && isBlockedAfter) {
                              return true // Found Closed Four
                          }
                     } else if threat == .openThree && pCount == 3 && eCount == 2 {
                           // Need both sides open (empty)
                           if isOpenBefore && isOpenAfter {
                               return true // Found Open Three
                           }
                     } else if threat == .closedThree && pCount == 3 && eCount == 2 {
                          // Need exactly one side blocked, one open
                          if (isBlockedBefore && isOpenAfter) || (isOpenBefore && isBlockedAfter) {
                              return true // Found Closed Three
                          }
                     }
                 } // End 5-window offset loop
            } // End if check threes/closed four
        } // End directions loop

        return false // No threat of the specified type found involving the last move
    }


    // --- Core logic helpers ---
    func placeAiPieceAndEndTurn(at position: Position) {
        // Ensure AI doesn't overwrite or go out of bounds (redundant check, but safe)
        guard checkBounds(row: position.row, col: position.col) && board[position.row][position.col] == .empty else {
            print("!!! AI INTERNAL ERROR: placeAiPieceAndEndTurn called with invalid position \(position). Current: \(board[position.row][position.col])")
            // Decide how to handle this - maybe pick a random valid move instead? For now, just log and potentially let switchPlayer handle it.
            // If we don't place a piece, switchPlayer won't happen automatically.
            // Let's try to recover by picking a random move.
            let recoveryMove = findEmptyCells().randomElement()
            if let move = recoveryMove {
                 print("!!! AI RECOVERY: Placing random piece at \(move) instead.")
                 placePiece(atRow: move.row, col: move.col) // Recursive call - potential risk? No, because placePiece has checks.
            } else {
                 print("!!! AI RECOVERY FAILED: No empty cells left?")
                 // Let game state proceed, likely a draw or error state.
                 view.isUserInteractionEnabled = true // Give back control
            }
            return
        }
        placePiece(atRow: position.row, col: position.col)
    }

    // Check if placing a piece for 'player' at 'position' results in immediate win
    func checkPotentialWin(player: Player, position: Position) -> Bool {
        var tempBoard = self.board;
        guard checkBounds(row: position.row, col: position.col) && tempBoard[position.row][position.col] == .empty else { return false };
        tempBoard[position.row][position.col] = state(for: player)
        return checkForWinOnBoard(boardToCheck: tempBoard, playerState: tempBoard[position.row][position.col], lastRow: position.row, lastCol: position.col)
    }

    // Check board for win condition centered around last move
    func checkForWinOnBoard(boardToCheck: [[CellState]], playerState: CellState, lastRow: Int, lastCol: Int) -> Bool {
        guard playerState != .empty else { return false }; let directions = [(0, 1), (1, 0), (1, 1), (1, -1)]; for (dr, dc) in directions { var count = 1;
            // Count positive direction
            for i in 1..<5 { let r = lastRow + dr * i; let c = lastCol + dc * i; if checkBounds(row: r, col: c) && boardToCheck[r][c] == playerState { count += 1 } else { break } };
            // Count negative direction
            for i in 1..<5 { let r = lastRow - dr * i; let c = lastCol - dc * i; if checkBounds(row: r, col: c) && boardToCheck[r][c] == playerState { count += 1 } else { break } };
            if count >= 5 { return true } }; return false
    }

    func findEmptyCells() -> [Position] {
        var emptyPositions: [Position] = [];
        for r in 0..<boardSize { for c in 0..<boardSize { if board[r][c] == .empty { emptyPositions.append(Position(row: r, col: c)) } } };
        return emptyPositions
    }

    // Find empty cells adjacent to *any* piece
    func findAdjacentEmptyCells() -> [Position] {
        var adjacentEmpty = Set<Position>(); let directions = [(-1,-1), (-1,0), (-1,1), (0,-1), (0,1), (1,-1), (1,0), (1,1)];
        for r in 0..<boardSize { for c in 0..<boardSize { if board[r][c] != .empty { for (dr, dc) in directions { let nr = r + dr; let nc = c + dc; if checkBounds(row: nr, col: nc) && board[nr][nc] == .empty { adjacentEmpty.insert(Position(row: nr, col: nc)) } } } } };
        return Array(adjacentEmpty)
    }

    struct Position: Hashable, Equatable { // Ensure Equatable for checking contains
        var row: Int; var col: Int
    }

    func isBoardFull() -> Bool {
        // Faster check: if findEmptyCells is empty
        return findEmptyCells().isEmpty
        // Original check:
        // for row in board { if row.contains(.empty) { return false } }; return true
    }
    func checkBounds(row: Int, col: Int) -> Bool { return row >= 0 && row < boardSize && col >= 0 && col < boardSize }
    
    // Helper to get player state enum from player enum
    func state(for player: Player) -> CellState {
        return player == .black ? .black : .white
    }

    // Helper to get opponent player enum
    func opponent(of player: Player) -> Player {
        return player == .black ? .white : .black
    }

    // --- Winning Line Drawing ---
    func drawWinningLine(positions: [Position]) {
        guard positions.count >= 2, cellSize > 0 else { return } // Need cell size
        winningLineLayer?.removeFromSuperlayer() // Remove old one if exists
        let path = UIBezierPath()
        let firstPos = positions.first!; let startX = boardPadding + CGFloat(firstPos.col) * cellSize; let startY = boardPadding + CGFloat(firstPos.row) * cellSize; path.move(to: CGPoint(x: startX, y: startY))
        let lastPos = positions.last!; let endX = boardPadding + CGFloat(lastPos.col) * cellSize; let endY = boardPadding + CGFloat(lastPos.row) * cellSize; path.addLine(to: CGPoint(x: endX, y: endY))
        let shapeLayer = CAShapeLayer()
        shapeLayer.path = path.cgPath; shapeLayer.strokeColor = UIColor.red.withAlphaComponent(0.8).cgColor; shapeLayer.lineWidth = 5.0
        shapeLayer.lineCap = .round; shapeLayer.lineJoin = .round; shapeLayer.name = "winningLine"
        shapeLayer.strokeEnd = 0.0 // Start not drawn

        boardView.layer.addSublayer(shapeLayer)
        self.winningLineLayer = shapeLayer

        let animation = CABasicAnimation(keyPath: "strokeEnd"); animation.fromValue = 0.0; animation.toValue = 1.0; animation.duration = 0.5; animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        shapeLayer.strokeEnd = 1.0 // Update model
        shapeLayer.add(animation, forKey: "drawLineAnimation")

        print("Winning line drawn.")
    }
    
    // --- Board State Getters (Not strictly needed by AI now, but useful helpers) ---
    func getRow(_ r: Int, on boardToCheck: [[CellState]]) -> [CellState] { guard r >= 0 && r < boardSize else { return [] }; return boardToCheck[r] }
    func getColumn(_ c: Int, on boardToCheck: [[CellState]]) -> [CellState] { guard c >= 0 && c < boardSize else { return [] }; return boardToCheck.map { $0[c] } }
    func getDiagonals(on boardToCheck: [[CellState]]) -> [[CellState]] { /* ... unchanged ... */
        var diagonals: [[CellState]] = []
        let n = boardSize
        guard !boardToCheck.isEmpty && boardToCheck.count == n && boardToCheck[0].count == n else { return [] }
        // Top-Left to Bottom-Right
        for c in 0..<n { var diag: [CellState] = []; var r_temp = 0; var c_temp = c; while checkBounds(row: r_temp, col: c_temp) { diag.append(boardToCheck[r_temp][c_temp]); r_temp += 1; c_temp += 1 }; if diag.count >= 5 { diagonals.append(diag) } }
        for r in 1..<n { var diag: [CellState] = []; var r_temp = r; var c_temp = 0; while checkBounds(row: r_temp, col: c_temp) { diag.append(boardToCheck[r_temp][c_temp]); r_temp += 1; c_temp += 1 }; if diag.count >= 5 { diagonals.append(diag) } }
        // Top-Right to Bottom-Left
        for c in 0..<n { var antiDiag: [CellState] = []; var r_temp = 0; var c_temp = c; while checkBounds(row: r_temp, col: c_temp) { antiDiag.append(boardToCheck[r_temp][c_temp]); r_temp += 1; c_temp -= 1 }; if antiDiag.count >= 5 { diagonals.append(antiDiag) } }
        for r in 1..<n { var antiDiag: [CellState] = []; var r_temp = r; var c_temp = n - 1; while checkBounds(row: r_temp, col: c_temp) { antiDiag.append(boardToCheck[r_temp][c_temp]); r_temp += 1; c_temp -= 1 }; if antiDiag.count >= 5 { diagonals.append(antiDiag) } }
        return diagonals
     }

    // --- Reset Button Logic ---
    @IBAction func resetButtonTapped(_ sender: UIButton) {
        print("Reset button DOWN")
        sender.transform = .identity
        UIView.animate(withDuration: 0.08, delay: 0, options: [.allowUserInteraction, .curveEaseOut], animations: {
             sender.transform = CGAffineTransform(scaleX: 0.94, y: 0.94)
              if #unavailable(iOS 15.0) { sender.backgroundColor = UIColor(red: 0.88, green: 0.89, blue: 0.91, alpha: 1.0) }
              else { sender.alpha = 0.85 }
        }, completion: nil)

         if currentGameState == .playing {
              print("Resetting game...")
              setupNewGame()
              // If AI was playing, ensure interaction is enabled for human if it's their turn now
              if !isAiTurn { view.isUserInteractionEnabled = true }
              // If it becomes AI's turn (e.g. AI is Black), startGame logic should handle the first move.
         } else { print("Reset tapped while in setup state - doing nothing.") }

         sender.addTarget(self, action: #selector(resetButtonReleased(_:)), for: .touchUpInside)
         sender.addTarget(self, action: #selector(resetButtonReleased(_:)), for: .touchUpOutside)
         sender.addTarget(self, action: #selector(resetButtonReleased(_:)), for: .touchCancel)
    }

    @IBAction func resetButtonReleased(_ sender: UIButton) {
        // print("Reset button RELEASED") // Too verbose
        UIView.animate(withDuration: 0.1, delay: 0, options: [.allowUserInteraction, .curveEaseIn], animations: {
            sender.transform = .identity
             if #unavailable(iOS 15.0) { sender.backgroundColor = UIColor(red: 0.95, green: 0.95, blue: 0.97, alpha: 1.0) }
             else { sender.alpha = 1.0 }
        }, completion: { _ in
            sender.removeTarget(self, action: #selector(self.resetButtonReleased(_:)), for: .touchUpInside)
            sender.removeTarget(self, action: #selector(self.resetButtonReleased(_:)), for: .touchUpOutside)
            sender.removeTarget(self, action: #selector(self.resetButtonReleased(_:)), for: .touchCancel)
        })
    }

} // End of ViewController class
