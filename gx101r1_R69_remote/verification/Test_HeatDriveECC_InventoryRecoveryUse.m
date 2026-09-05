function Test_HeatDriveECC_InventoryRecoveryUse()
    contract.control_volume_basis_review = struct( ...
        'production_continuation_allowed', false, ...
        'strict_inventory_diagnostic_allowed', true);
    expect_reject(contract, struct(), 'HeatDriveECC:InventoryBasisUnderReview');
    expect_reject(contract, struct('recovery_use', 'same_parameter_continuation'), ...
        'HeatDriveECC:InventoryBasisUnderReview');
    Assert_HeatDriveECC_InventoryRecoveryUse(contract, ...
        struct('recovery_use', 'inventory_diagnostic'));
    contract.control_volume_basis_review.strict_inventory_diagnostic_allowed = false;
    expect_reject(contract, struct('recovery_use', 'inventory_diagnostic'), ...
        'HeatDriveECC:InventoryBasisUnderReview');
    contract.control_volume_basis_review.production_continuation_allowed = 'false';
    expect_reject(contract, struct(), 'HeatDriveECC:InvalidInventoryRecoveryPolicy');
    fprintf('INVENTORY_RECOVERY_USE_TEST_PASS=1 CASES=5\n');
end

function expect_reject(contract, settings, identifier)
    caught = false;
    try
        Assert_HeatDriveECC_InventoryRecoveryUse(contract, settings);
    catch e
        caught = true;
        assert(strcmp(e.identifier, identifier), '%s', e.message);
    end
    assert(caught, 'Expected a fail-closed recovery policy.');
end
