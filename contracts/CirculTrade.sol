// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * ============================================================
 *  CirculTrade — Decentralized Escrow for the Circular Economy
 * ============================================================
 * Basado en el Reporte Final "CirculTrade: Decentralized Escrow
 * for Circular Economy" (LACNet, EVM-compatible, Pro-Testnet).
 *
 * Máquina de estados (Sección 7.5 del reporte):
 *   Created -> Funded -> Shipped -> Completed
 *                            |-> Disputed -> Completed (paga a Seller)
 *                                         -> Refunded  (reembolsa a Buyer)
 *
 * Arquitectura:
 *   - CirculTradeEscrow: contrato individual, un depósito por ítem.
 *   - CirculTradeFactory: despliega instancias de CirculTradeEscrow
 *     (una por transacción) y mantiene un registro + reputación
 *     on-chain no transferible por dirección (Sección 7.4).
 * ============================================================
 */

/// @title CirculTradeEscrow
/// @notice Contrato de depósito en garantía (escrow) para una única
///         transacción peer-to-peer de bienes de segunda mano.
contract CirculTradeEscrow is ReentrancyGuard {

    // ---------------------------------------------------------------
    // Máquina de Estados
    // ---------------------------------------------------------------
    enum State {
        Created,    // 1. Contrato desplegado, esperando fondeo del comprador
        Funded,     // 2. Fondos del comprador bloqueados en el contrato
        Shipped,    // 3. Vendedor declara haber enviado / entregado el ítem
        Completed,  // 5a. Fondos liberados al vendedor
        Disputed,   // 5b. Comprador impugnó el estado del ítem
        Refunded    // 7. Fondos devueltos al comprador tras resolución
    }

    State public state;

    // ---------------------------------------------------------------
    // Roles (Sección 5.1 y 7.2 del reporte: Buyer, Seller, Arbiter)
    // ---------------------------------------------------------------
    address public immutable buyer;
    address public immutable seller;
    address public immutable arbiter;      // Rol de Oráculo / Arbitraje (paso 6)
    address public immutable factory;      // Referencia al factory para reputación

    // ---------------------------------------------------------------
    // Términos económicos de la transacción
    // ---------------------------------------------------------------
    uint256 public immutable price;                 // Precio acordado (wei)
    string  public itemDescription;                 // Descripción del ítem (hash/URI recomendado)
    uint256 public immutable confirmationWindow;     // Ventana para confirmar/disputar (segundos)
    uint256 public shippedAt;                        // Timestamp de marcado "Shipped"

    // ---------------------------------------------------------------
    // Eventos — permiten reconstruir el "on-chain record" citado en
    // la Sección 7.4 (verifiable on-chain record -> reputation score)
    // ---------------------------------------------------------------
    event Funded(address indexed buyer, uint256 amount);
    event Shipped(address indexed seller, uint256 timestamp);
    event ReceiptConfirmed(address indexed buyer, uint256 amountReleased);
    event DisputeOpened(address indexed initiator, string reason);
    event DisputeResolved(address indexed arbiter, bool releasedToSeller, uint256 amount);
    event TimeoutClaimed(address indexed seller, uint256 amount);

    // ---------------------------------------------------------------
    // Modificadores de control de acceso y de estado
    // ---------------------------------------------------------------
    modifier onlyBuyer() {
        require(msg.sender == buyer, "CirculTrade: solo el comprador");
        _;
    }

    modifier onlySeller() {
        require(msg.sender == seller, "CirculTrade: solo el vendedor");
        _;
    }

    modifier onlyArbiter() {
        require(msg.sender == arbiter, "CirculTrade: solo el arbitro/oraculo");
        _;
    }

    modifier onlyParties() {
        require(
            msg.sender == buyer || msg.sender == seller,
            "CirculTrade: solo comprador o vendedor"
        );
        _;
    }

    modifier inState(State _state) {
        require(state == _state, "CirculTrade: estado invalido para esta accion");
        _;
    }

    /// @param _buyer Direccion del comprador
    /// @param _seller Direccion del vendedor
    /// @param _arbiter Direccion del arbitro/oraculo de disputas
    /// @param _price Precio acordado en wei
    /// @param _itemDescription Descripcion o hash IPFS del ítem
    /// @param _confirmationWindow Ventana en segundos para confirmar o disputar
    constructor(
        address _buyer,
        address _seller,
        address _arbiter,
        uint256 _price,
        string memory _itemDescription,
        uint256 _confirmationWindow
    ) {
        require(_buyer != address(0) && _seller != address(0) && _arbiter != address(0), "CirculTrade: direccion invalida");
        require(_buyer != _seller, "CirculTrade: comprador y vendedor no pueden ser iguales");
        require(_price > 0, "CirculTrade: precio debe ser mayor a 0");
        require(_confirmationWindow > 0, "CirculTrade: ventana debe ser mayor a 0");

        buyer = _buyer;
        seller = _seller;
        arbiter = _arbiter;
        factory = msg.sender; // el Factory despliega este contrato
        price = _price;
        itemDescription = _itemDescription;
        confirmationWindow = _confirmationWindow;
        state = State.Created;
    }

    // -----------------------------------------------------------
    // 1 -> 2. BUYER selecciona el ítem y envía el pago (fondeo)
    // -----------------------------------------------------------
    function fund() external payable onlyBuyer inState(State.Created) {
        require(msg.value == price, "CirculTrade: el monto enviado debe ser igual al precio");
        state = State.Funded;
        emit Funded(msg.sender, msg.value);
    }

    // -----------------------------------------------------------
    // 3. SELLER marca el ítem como enviado / entregado
    // -----------------------------------------------------------
    function markShipped() external onlySeller inState(State.Funded) {
        state = State.Shipped;
        shippedAt = block.timestamp;
        emit Shipped(msg.sender, block.timestamp);
    }

    // -----------------------------------------------------------
    // 4 -> 5a. BUYER inspecciona y confirma recepción -> RELEASE
    // Patrón Checks-Effects-Interactions + nonReentrant como
    // defensa en profundidad contra reentrancy.
    // -----------------------------------------------------------
    function confirmReceipt() external onlyBuyer inState(State.Shipped) nonReentrant {
        // Effects (antes de la interacción externa)
        state = State.Completed;
        uint256 amount = price;

        // Interaction
        (bool success, ) = payable(seller).call{value: amount}("");
        require(success, "CirculTrade: transferencia al vendedor fallida");

        emit ReceiptConfirmed(msg.sender, amount);
        _reportOutcome(true);
    }

    // -----------------------------------------------------------
    // 4 -> 5b. Cualquiera de las partes abre una disputa dentro
    // de la ventana de confirmación (ítem no descrito correctamente)
    // -----------------------------------------------------------
    function openDispute(string calldata reason) external onlyParties inState(State.Shipped) {
        require(
            block.timestamp <= shippedAt + confirmationWindow,
            "CirculTrade: ventana de disputa expirada"
        );
        state = State.Disputed;
        emit DisputeOpened(msg.sender, reason);
    }

    // -----------------------------------------------------------
    // 6 -> 7. ARBITER revisa evidencia y resuelve la disputa
    // -----------------------------------------------------------
    function resolveDispute(bool releaseToSeller)
        external
        onlyArbiter
        inState(State.Disputed)
        nonReentrant
    {
        uint256 amount = price;

        if (releaseToSeller) {
            state = State.Completed;
            (bool success, ) = payable(seller).call{value: amount}("");
            require(success, "CirculTrade: transferencia al vendedor fallida");
        } else {
            state = State.Refunded;
            (bool success, ) = payable(buyer).call{value: amount}("");
            require(success, "CirculTrade: reembolso al comprador fallido");
        }

        emit DisputeResolved(msg.sender, releaseToSeller, amount);
        _reportOutcome(releaseToSeller);
    }

    // -----------------------------------------------------------
    // Salvaguarda anti-abandono: si el comprador nunca confirma ni
    // disputa dentro de la ventana pactada, el vendedor puede
    // reclamar los fondos (evita que el comprador bloquee el pago
    // indefinidamente por inacción — riesgo moral inverso).
    // -----------------------------------------------------------
    function claimAfterTimeout() external onlySeller inState(State.Shipped) nonReentrant {
        require(
            block.timestamp > shippedAt + confirmationWindow,
            "CirculTrade: ventana de confirmacion aun activa"
        );
        state = State.Completed;
        uint256 amount = price;

        (bool success, ) = payable(seller).call{value: amount}("");
        require(success, "CirculTrade: transferencia al vendedor fallida");

        emit TimeoutClaimed(msg.sender, amount);
        _reportOutcome(true);
    }

    // -----------------------------------------------------------
    // Reporta el resultado final al Factory para actualizar el
    // "Trust Score" no transferible por dirección (Seccion 7.4)
    // -----------------------------------------------------------
    function _reportOutcome(bool successfulForSeller) private {
        if (factory != address(0) && factory.code.length > 0) {
            // Llamada de bajo nivel para no romper el flujo del
            // escrow si el factory no implementa el hook (opcional).
            (bool ok, ) = factory.call(
                abi.encodeWithSignature(
                    "recordOutcome(address,address,bool)",
                    buyer,
                    seller,
                    successfulForSeller
                )
            );
            ok; // resultado ignorado intencionalmente: no debe revertir el escrow
        }
    }

    /// @notice Devuelve el balance actualmente bloqueado en el contrato
    function getBalance() external view returns (uint256) {
        return address(this).balance;
    }
}

/// @title CirculTradeFactory
/// @notice Despliega un contrato CirculTradeEscrow independiente por
///         cada transacción (modelo de "factoría de depósitos
///         individuales por ítem", Sección 5 del reporte) y mantiene
///         un registro consultable + reputación on-chain agregada.
contract CirculTradeFactory {

    struct EscrowRecord {
        address escrowAddress;
        address buyer;
        address seller;
        address arbiter;
        uint256 price;
        uint256 createdAt;
    }

    EscrowRecord[] public escrows;
    mapping(address => bool) public isCirculTradeEscrow;

    // Reputación no transferible: contadores de transacciones
    // completadas exitosamente vs. disputas resueltas en contra.
    mapping(address => uint256) public successfulTransactions;
    mapping(address => uint256) public disputesLostAsSeller;

    event EscrowCreated(
        address indexed escrowAddress,
        address indexed buyer,
        address indexed seller,
        address arbiter,
        uint256 price
    );

    event OutcomeRecorded(address indexed party, bool positive);

    /// @notice Crea y despliega un nuevo contrato de escrow para un ítem.
    /// @param _seller Direccion del vendedor
    /// @param _arbiter Direccion del arbitro/oraculo de disputas
    /// @param _price Precio acordado en wei
    /// @param _itemDescription Descripcion o hash IPFS del ítem
    /// @param _confirmationWindow Ventana en segundos para confirmar o disputar
    function createEscrow(
        address _seller,
        address _arbiter,
        uint256 _price,
        string calldata _itemDescription,
        uint256 _confirmationWindow
    ) external returns (address escrowAddress) {
        CirculTradeEscrow newEscrow = new CirculTradeEscrow(
            msg.sender,       // buyer = quien invoca la creacion
            _seller,
            _arbiter,
            _price,
            _itemDescription,
            _confirmationWindow
        );

        escrowAddress = address(newEscrow);
        isCirculTradeEscrow[escrowAddress] = true;

        escrows.push(EscrowRecord({
            escrowAddress: escrowAddress,
            buyer: msg.sender,
            seller: _seller,
            arbiter: _arbiter,
            price: _price,
            createdAt: block.timestamp
        }));

        emit EscrowCreated(escrowAddress, msg.sender, _seller, _arbiter, _price);
    }

    /// @notice Hook invocado únicamente por contratos de escrow desplegados
    ///         por este factory, para actualizar el Trust Score on-chain.
    function recordOutcome(address _buyer, address _seller, bool releasedToSeller) external {
        require(isCirculTradeEscrow[msg.sender], "CirculTrade: caller no autorizado");

        if (releasedToSeller) {
            successfulTransactions[_seller] += 1;
            successfulTransactions[_buyer] += 1;
            emit OutcomeRecorded(_seller, true);
            emit OutcomeRecorded(_buyer, true);
        } else {
            disputesLostAsSeller[_seller] += 1;
            emit OutcomeRecorded(_seller, false);
        }
    }

    /// @notice Numero total de escrows creados a traves del factory.
    function totalEscrows() external view returns (uint256) {
        return escrows.length;
    }

    /// @notice Trust Score simple: transacciones exitosas menos disputas perdidas.
    function trustScore(address user) external view returns (int256) {
        return int256(successfulTransactions[user]) - int256(disputesLostAsSeller[user]);
    }
}

